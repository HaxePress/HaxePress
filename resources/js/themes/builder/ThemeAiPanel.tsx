import { useEffect, useRef, useState } from 'react';
import { useTranslation } from '../../i18n';
import Icon from '../../components/Icon';
import Alert from '../../components/Alert';
import type useThemeAiSync from './useThemeAiSync';
import type { AiPermissions } from './ThemeDesignerConnection';

interface Connection {
  websocket: boolean;
  permissions: AiPermissions;
  mediaAllowed: boolean;
}

export default function ThemeAiPanel({
  id,
  csrfToken,
  onClose,
  collaboration,
}: {
  id: string;
  csrfToken: string | null;
  onClose: () => void;
  collaboration: ReturnType<typeof useThemeAiSync>;
}) {
  const { t } = useTranslation();
  const [connection, setConnection] = useState<Connection | null>(null);
  const [permissions, setPermissions] = useState<AiPermissions>({
    read: false,
    edit: false,
    media: false,
  });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const dialog = useRef<HTMLDialogElement>(null);

  async function update() {
    setBusy(true);
    setError('');
    setNotice('');
    try {
      const response = await fetch(`/admin/themes/${id}/ai`, {
        headers: { Accept: 'application/json', 'X-CSRF-TOKEN': csrfToken || '' },
      });
      if (!response.ok || !response.headers.get('content-type')?.includes('application/json'))
        throw new Error();
      const result: Connection = await response.json();
      setConnection(result);
      setPermissions(result.permissions);
    } catch {
      setError('The AI connection could not be updated.');
    } finally {
      setBusy(false);
    }
  }

  async function savePermissions() {
    setBusy(true);
    setError('');
    setNotice('');
    try {
      const response = await fetch(`/admin/themes/${id}/ai/permissions`, {
        method: 'POST',
        headers: {
          Accept: 'application/json',
          'Content-Type': 'application/json',
          'X-CSRF-TOKEN': csrfToken || '',
        },
        body: JSON.stringify({
          read: permissions.read ? '1' : '0',
          edit: permissions.edit ? '1' : '0',
          media: permissions.media ? '1' : '0',
        }),
      });
      if (!response.ok) throw new Error();
      const result = await response.json();
      setPermissions(result.permissions);
      setNotice('AI permissions saved.');
    } catch {
      setError('AI permissions could not be saved.');
    } finally {
      setBusy(false);
    }
  }

  useEffect(() => {
    void update();
  }, [id]);
  useEffect(() => {
    if (dialog.current && !dialog.current.open) dialog.current.showModal();
  }, []);

  async function copyBrowserApi() {
    try {
      await navigator.clipboard.writeText('await window.haxePress.themeDesigner.listTools()');
      setNotice('Browser API example copied.');
    } catch {
      setError('The browser API example could not be copied.');
    }
  }

  return (
    <dialog
      ref={dialog}
      className="theme-ai-panel"
      aria-labelledby="theme-ai-title"
      onCancel={(event) => {
        event.preventDefault();
        if (!busy) onClose();
      }}
    >
      <div className="easy-panel-title">
        <h2 id="theme-ai-title">
          <Icon name="sparkles" />
          {t('AI collaboration')}
        </h2>
        <button
          className="icon-button"
          type="button"
          aria-label={t('Close AI connection')}
          disabled={busy}
          onClick={onClose}
        >
          <Icon name="x" />
        </button>
      </div>
      <Alert error message={t(error)} />
      <Alert message={t(notice)} />
      <div className="theme-ai-presence" aria-live="polite">
        <span>
          {t(
            collaboration.status === 'connected'
              ? 'Browser connected'
              : collaboration.status === 'connecting'
                ? 'Connecting browser…'
                : 'Browser disconnected',
          )}
        </span>
        {collaboration.status === 'disconnected' && (
          <button
            className="button button-outline"
            type="button"
            onClick={() => collaboration.connection?.reconnect()}
          >
            {t('Reconnect')}
          </button>
        )}
      </div>
      <div className="theme-ai-credentials">
        <h3>{t('Browser tools')}</h3>
        <p className="field-help">
          {t(
            'Browser extensions can call the same tools through the page API. Changes arrive live through this connection.',
          )}
        </p>
        <code>window.haxePress.themeDesigner</code>
        <button
          className="button button-outline"
          type="button"
          onClick={() => void copyBrowserApi()}
        >
          <Icon name="copy" />
          {t('Copy browser API example')}
        </button>
      </div>
      {connection && (
        <>
          <fieldset className="theme-ai-permissions" disabled={busy}>
            <legend>{t('AI permissions')}</legend>
            <p className="field-help">
              {t(
                'These permissions apply to your browser tools and AI connections for this theme.',
              )}
            </p>
            <label>
              <input
                type="checkbox"
                checked={permissions.read}
                onChange={(event) =>
                  setPermissions((previous) => ({
                    ...previous,
                    read: event.target.checked,
                    edit: event.target.checked && previous.edit,
                    media: event.target.checked && previous.media,
                  }))
                }
              />
              {t('Read design')}
            </label>
            <label>
              <input
                type="checkbox"
                checked={permissions.edit}
                disabled={!permissions.read}
                onChange={(event) =>
                  setPermissions((previous) => ({ ...previous, edit: event.target.checked }))
                }
              />
              {t('Edit design draft')}
            </label>
            <label>
              <input
                type="checkbox"
                checked={permissions.media}
                disabled={!permissions.read || !connection.mediaAllowed}
                onChange={(event) =>
                  setPermissions((previous) => ({ ...previous, media: event.target.checked }))
                }
              />
              {t('Browse media')}
            </label>
            <button
              className="button button-outline"
              type="button"
              onClick={() => void savePermissions()}
            >
              {t('Save permissions')}
            </button>
          </fieldset>
          <div className="theme-ai-credentials">
            <button
              className="button button-outline"
              type="button"
              onClick={() => {
                onClose();
                window.dispatchEvent(new Event('haxepress:connect-ai'));
              }}
            >
              {t('Connect AI')}
            </button>
          </div>
        </>
      )}
      <p className="field-help">
        {t('AI edits stay in the draft. Publish from the editor when ready.')}
      </p>
    </dialog>
  );
}
