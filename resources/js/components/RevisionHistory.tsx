import { useTranslation } from '../i18n';
import { router, usePage } from '@inertiajs/react';
import { useState } from 'react';
import Markdown from './Markdown';
import type { ContentItem, SharedProps } from '../types';

interface Revision {
  id: number;
  version: number;
  title: string;
  author: string | null;
  created_at: string;
}

export default function RevisionHistory({
  base,
  id,
  beforeRestore,
}: {
  base: string;
  id: string;
  beforeRestore: () => void;
}) {
  const { t } = useTranslation();
  const { csrfToken } = usePage<SharedProps>().props;
  const [open, setOpen] = useState(false);
  const [revisions, setRevisions] = useState<Revision[]>([]);
  const [preview, setPreview] = useState<{ revision: Revision; snapshot: ContentItem } | null>(
    null,
  );
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  async function load() {
    setBusy(true);
    try {
      const response = await fetch(`${base}/${id}/history`, {
        headers: { Accept: 'application/json' },
      });
      if (!response.ok) throw new Error('History could not be loaded.');
      setRevisions((await response.json()).revisions);
      setOpen(true);
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : 'History could not be loaded.');
    } finally {
      setBusy(false);
    }
  }
  return (
    <section className="admin-card revision-panel">
      <div className="revision-heading">
        <h2>{t('Revision history')}</h2>
        <button
          className="button button-outline"
          type="button"
          disabled={busy}
          onClick={() => (open ? setOpen(false) : void load())}
        >
          {open ? t('Close history') : busy ? t('Loading…') : t('View revisions')}
        </button>
      </div>
      {error && <p role="alert">{t(error)}</p>}
      {open && (
        <>
          <p className="field-help">
            {t(
              'The latest 50 saved versions are kept. Restore opens a working copy for review before you save it.',
            )}
          </p>
          {revisions.length === 0 ? (
            <p>{t('No saved revisions yet.')}</p>
          ) : (
            <ol className="revision-list">
              {revisions.map((revision) => (
                <li key={revision.id}>
                  <div>
                    <strong>
                      {t('Version')} {revision.version}
                    </strong>
                    <span>
                      {revision.created_at} · {revision.author || t('System')}
                    </span>
                  </div>
                  <button
                    className="button button-outline"
                    type="button"
                    onClick={async () => {
                      try {
                        const response = await fetch(`${base}/${id}/history/${revision.id}`, {
                          headers: { Accept: 'application/json' },
                        });
                        if (!response.ok) throw new Error('This revision could not be loaded.');
                        setPreview({ revision, snapshot: (await response.json()).snapshot });
                      } catch (failure) {
                        setError(
                          failure instanceof Error
                            ? failure.message
                            : 'Revision could not be loaded.',
                        );
                      }
                    }}
                  >
                    {t('Preview')}
                  </button>
                </li>
              ))}
            </ol>
          )}
          {preview && (
            <div className="revision-preview">
              <h3>{preview.snapshot.title}</h3>
              <div className="content-prose">
                <Markdown content={preview.snapshot.content || ''} />
              </div>
              <button
                className="button"
                type="button"
                onClick={() => {
                  beforeRestore();
                  router.post(
                    `${base}/${id}/history/${preview.revision.id}/restore`,
                    { _token: csrfToken },
                    { preserveState: false },
                  );
                }}
              >
                {t('Restore version')} {preview.revision.version} {t('as working copy')}
              </button>
            </div>
          )}
        </>
      )}
    </section>
  );
}
