import { useEffect, useRef, useState } from 'react';
import { useTranslation } from '../i18n';
import { startAdminMcp, type AdminMcpStatus } from '../ai/AdminMcpBrowser';
import {
  browserPrompt,
  clientChoices,
  connectionDetails,
  profiles,
  setupInstructions,
  type ClientChoice,
  type McpConnection,
  type RemoteProfile,
} from '../ai/admin-connection-prompt';
import AiClientMark from './AiClientMark';
import Alert from './Alert';
import Icon from './Icon';

interface McpSession extends Omit<McpConnection, 'token'> {
  firstSeenAt: number | null;
  lastSeenAt: number | null;
}

interface AiState {
  sessions: McpSession[];
  hosted: boolean;
}

/** How long a new MCP link lasts, in hours; the server accepts these values. */
const lifetimes = [1, 24, 168, 720] as const;
type Lifetime = (typeof lifetimes)[number];
const lifetimeLabels: Record<Lifetime, string> = {
  1: '1 hour',
  24: '1 day',
  168: '7 days',
  720: '30 days',
};
const lifetimeFromNow: Record<Lifetime, string> = {
  1: '1 hour from now',
  24: '1 day from now',
  168: '7 days from now',
  720: '30 days from now',
};

export default function AdminAiControl({
  adminId,
  csrfToken,
}: {
  adminId: number;
  csrfToken: string | null;
}) {
  const { t, locale } = useTranslation();
  const [status, setStatus] = useState<AdminMcpStatus>('connecting');
  const [state, setState] = useState<AiState | null>(null);
  const [profile, setProfile] = useState<ClientChoice>('web');
  const [useCodexCli, setUseCodexCli] = useState(false);
  const [hours, setHours] = useState<Lifetime>(24);
  const [connection, setConnection] = useState<McpConnection | null>(null);
  const [show, setShow] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const dialog = useRef<HTMLDialogElement>(null);
  const requestIndex = useRef(0);
  const remote = connection?.profile === profile ? connection : null;
  const setupProfile = profile === 'chatgpt' && useCodexCli ? 'codex' : profile;
  let details = '';
  if (setupProfile === 'web') {
    details = browserPrompt;
  } else if (remote) {
    details = connectionDetails(remote, setupProfile);
  }
  const hasSessions = Boolean(state?.sessions.length);

  async function refresh(): Promise<AiState | null> {
    const index = ++requestIndex.current;
    try {
      const response = await fetch('/admin/ai', {
        headers: { Accept: 'application/json' },
        signal: AbortSignal.timeout(10000),
      });
      if (!response.ok || response.redirected) return null;
      const next: AiState = await response.json();
      if (index !== requestIndex.current) return null;
      setState(next);
      setConnection((current) =>
        current && next.sessions.some((session) => session.id === current.id) ? current : null,
      );
      return next;
    } catch {
      return null;
    }
  }

  function open() {
    setShow(true);
    void refresh();
  }

  useEffect(() => {
    let stopped = false;
    let stop: (() => void) | undefined;
    setConnection(null);
    setState(null);
    void refresh().then((initial) => {
      if (stopped) return;
      if (initial?.hosted === false) {
        setStatus('disconnected');
        return;
      }
      stop = startAdminMcp(setStatus, () => void refresh());
    });
    window.addEventListener('haxepress:connect-ai', open);
    return () => {
      stopped = true;
      requestIndex.current++;
      stop?.();
      window.removeEventListener('haxepress:connect-ai', open);
    };
  }, [adminId]);

  useEffect(() => {
    if (show && dialog.current && !dialog.current.open) dialog.current.showModal();
  }, [show]);

  useEffect(() => {
    if (!show || !hasSessions) return;
    const interval = window.setInterval(() => void refresh(), 10000);
    return () => window.clearInterval(interval);
  }, [show, hasSessions]);

  async function change(method: 'POST' | 'DELETE', selection: RemoteProfile | string) {
    setBusy(true);
    setError('');
    setNotice('');
    try {
      const path = method === 'POST' ? '/admin/ai/sessions' : `/admin/ai/sessions/${selection}`;
      const response = await fetch(path, {
        method,
        headers: {
          Accept: 'application/json',
          'Content-Type': 'application/json',
          'X-CSRF-TOKEN': csrfToken || '',
        },
        ...(method === 'POST' && { body: JSON.stringify({ profile: selection, hours }) }),
        signal: AbortSignal.timeout(15000),
      });
      const result = await response.json().catch(() => null);
      if (!response.ok || !result || response.redirected) {
        throw new Error(result?.error || 'The AI connection could not be updated.');
      }
      if (method === 'POST') {
        setConnection(result);
      } else {
        setConnection((current) => (current?.id === selection ? null : current));
      }
    } catch (failure) {
      setError(
        failure instanceof Error ? failure.message : 'The AI connection could not be updated.',
      );
    } finally {
      await refresh();
      setBusy(false);
    }
  }

  /** A link no client has used yet gets a new expiry, counted from now. */
  async function changeExpiry(id: string, lifetime: Lifetime) {
    setBusy(true);
    setError('');
    setNotice('');
    try {
      const response = await fetch(`/admin/ai/sessions/${id}/expiry`, {
        method: 'POST',
        headers: {
          Accept: 'application/json',
          'Content-Type': 'application/json',
          'X-CSRF-TOKEN': csrfToken || '',
        },
        body: JSON.stringify({ hours: lifetime }),
        signal: AbortSignal.timeout(15000),
      });
      const result = await response.json().catch(() => null);
      if (!response.ok || !result || response.redirected) {
        throw new Error(result?.error || 'The expiry could not be changed.');
      }
      setNotice('The expiry was changed.');
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : 'The expiry could not be changed.');
    } finally {
      await refresh();
      setBusy(false);
    }
  }

  async function copy(value: string) {
    try {
      await navigator.clipboard.writeText(value);
      setNotice('Connection details copied.');
      setError('');
    } catch {
      setError('The connection details could not be copied.');
    }
  }

  return (
    <>
      <button
        className="button button-outline admin-ai-trigger"
        type="button"
        aria-label={t('Connect AI')}
        aria-haspopup="dialog"
        onClick={open}
      >
        <Icon name="sparkles" />
        <span>{t('Connect AI')}</span>
      </button>
      {show && (
        <dialog
          ref={dialog}
          className="theme-ai-panel admin-ai-panel"
          aria-labelledby="admin-ai-title"
          onCancel={(event) => {
            event.preventDefault();
            setShow(false);
          }}
        >
          <div className="easy-panel-title">
            <h2 id="admin-ai-title">
              <Icon name="sparkles" />
              {t('Connect AI')}
            </h2>
            <button
              className="icon-button"
              type="button"
              aria-label={t('Close AI connection')}
              onClick={() => setShow(false)}
            >
              <Icon name="x" />
            </button>
          </div>
          <div className="admin-ai-client-grid" role="group" aria-label={t('MCP client')}>
            {clientChoices.map((item) => (
              <button
                key={item}
                className="admin-ai-client"
                type="button"
                aria-pressed={item === profile}
                onClick={() => {
                  setProfile(item);
                  setError('');
                  setNotice('');
                }}
              >
                <AiClientMark client={item} />
                <span>{t(profiles[item])}</span>
              </button>
            ))}
          </div>
          <Alert error message={error} />
          <Alert message={notice} />
          <div className="theme-ai-credentials">
            {setupProfile === 'web' ? (
              <div className="theme-ai-presence" aria-live="polite">
                {t(
                  status === 'connected'
                    ? 'Browser connected'
                    : status === 'connecting'
                      ? 'Connecting browser…'
                      : 'Browser disconnected',
                )}
                <code>window.haxePress.adminMcp</code>
              </div>
            ) : (
              <>
                {profile === 'chatgpt' && (
                  <div className="easy-mode-switch" role="group" aria-label={t('Setup format')}>
                    <button
                      type="button"
                      aria-pressed={!useCodexCli}
                      onClick={() => {
                        setUseCodexCli(false);
                        setNotice('');
                      }}
                    >
                      {t('Shared configuration')}
                    </button>
                    <button
                      type="button"
                      aria-pressed={useCodexCli}
                      onClick={() => {
                        setUseCodexCli(true);
                        setNotice('');
                      }}
                    >
                      {t('Codex CLI')}
                    </button>
                  </div>
                )}
                <p className="field-help">{t(setupInstructions[setupProfile])}</p>
                <div className="admin-ai-generate">
                  <label>
                    {t('Link expires after')}
                    <select
                      value={hours}
                      disabled={busy}
                      onChange={(event) => setHours(Number(event.target.value) as Lifetime)}
                    >
                      {lifetimes.map((lifetime) => (
                        <option key={lifetime} value={lifetime}>
                          {t(lifetimeLabels[lifetime])}
                        </option>
                      ))}
                    </select>
                  </label>
                  <button
                    className="button"
                    type="button"
                    disabled={busy || !state?.hosted}
                    onClick={() => void change('POST', profile)}
                  >
                    {t('Generate MCP connection')}
                  </button>
                </div>
                {remote && (
                  <label>
                    {t('MCP URL')}
                    <input value={remote.url} readOnly />
                  </label>
                )}
              </>
            )}
            {details && (
              <>
                <label>
                  {t(profile === 'web' ? 'Connection prompt' : 'Connection details')}
                  <textarea
                    rows={profile === 'web' ? 7 : 4}
                    readOnly
                    value={details}
                    spellCheck={false}
                  />
                </label>
                <button
                  className="button button-outline"
                  type="button"
                  onClick={() => void copy(details)}
                >
                  <Icon name="copy" />
                  {t(profile === 'web' ? 'Copy connection prompt' : 'Copy connection details')}
                </button>
              </>
            )}
          </div>
          {hasSessions && <h3>{t('Remote sessions')}</h3>}
          {state?.sessions.map((session) => (
            <div className="admin-ai-session" key={session.id}>
              <div>
                <strong>
                  {t(profiles[session.profile])} · {session.id.slice(0, 8)}
                </strong>
                <small>
                  {t('Expires {time}', { time: new Date(session.expires).toLocaleString(locale) })}
                </small>
                {session.firstSeenAt != null && session.lastSeenAt != null ? (
                  <>
                    <small>
                      {t('First seen {time}', {
                        time: new Date(session.firstSeenAt).toLocaleString(locale),
                      })}
                    </small>
                    <small>
                      {t('Last seen {time}', {
                        time: new Date(session.lastSeenAt).toLocaleString(locale),
                      })}
                    </small>
                  </>
                ) : (
                  <>
                    <small>{t('Not used yet')}</small>
                    <label className="admin-ai-expiry">
                      {t('Change expiry')}
                      <select
                        value=""
                        disabled={busy}
                        onChange={(event) =>
                          void changeExpiry(session.id, Number(event.target.value) as Lifetime)
                        }
                      >
                        <option value="" disabled>
                          {t('Choose a new expiry')}
                        </option>
                        {lifetimes.map((lifetime) => (
                          <option key={lifetime} value={lifetime}>
                            {t(lifetimeFromNow[lifetime])}
                          </option>
                        ))}
                      </select>
                    </label>
                  </>
                )}
              </div>
              <div className="admin-ai-actions">
                <button
                  className="button button-outline"
                  type="button"
                  onClick={() => void copy(session.url)}
                >
                  {t('Copy URL')}
                </button>
                <button
                  className="button button-outline"
                  type="button"
                  disabled={busy}
                  onClick={() => void change('DELETE', session.id)}
                >
                  {t('Revoke session')}
                </button>
              </div>
            </div>
          ))}
        </dialog>
      )}
    </>
  );
}
