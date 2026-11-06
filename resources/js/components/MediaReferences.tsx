import { useEffect, useRef, useState } from 'react';
import { useTranslation } from '../i18n';
import type { MediaImage } from '../types';
import Icon from './Icon';

interface Reference {
  id: string;
  type: string;
  title: string;
  detail: string;
  href: string | null;
  restricted: boolean;
}

export default function MediaReferences({
  image,
  onClose,
  onChecked,
}: {
  image: MediaImage | null;
  onClose: () => void;
  onChecked: (id: number, canDelete: boolean, verified: boolean) => void;
}) {
  const { t } = useTranslation();
  const dialog = useRef<HTMLDialogElement>(null);
  const abort = useRef<AbortController | null>(null);
  const [items, setItems] = useState<Reference[]>([]);
  const [next, setNext] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [verified, setVerified] = useState(true);
  const [canDelete, setCanDelete] = useState(false);

  async function load(path: string, replace: boolean, imageId: number) {
    abort.current?.abort();
    const controller = new AbortController();
    abort.current = controller;
    setBusy(true);
    setError('');
    try {
      const response = await fetch(path, {
        headers: { Accept: 'application/json' },
        signal: controller.signal,
      });
      if (
        response.redirected ||
        !response.headers.get('content-type')?.includes('application/json')
      ) {
        throw new Error('Sign in again to view references.');
      }
      if (!response.ok) throw new Error('References could not be loaded. Try again.');
      const data: {
        items: Reference[];
        next: string | null;
        canDelete: boolean;
        verified: boolean;
      } = await response.json();
      if (controller.signal.aborted) return;
      setItems((current) => (replace ? data.items : [...current, ...data.items]));
      setNext(data.next);
      setVerified(data.verified);
      setCanDelete(data.canDelete);
      onChecked(imageId, data.canDelete, data.verified);
    } catch (failure) {
      if (!controller.signal.aborted) {
        setError(
          failure instanceof Error ? failure.message : 'References could not be loaded. Try again.',
        );
        onChecked(imageId, false, false);
      }
    } finally {
      if (!controller.signal.aborted) setBusy(false);
    }
  }

  useEffect(() => {
    const element = dialog.current;
    if (image) {
      setItems([]);
      setNext(null);
      setVerified(true);
      if (!element?.open) element?.showModal();
      void load(`/admin/media/${image.id}/references`, true, image.id);
    } else if (element?.open) {
      element.close();
    }
    return () => abort.current?.abort();
  }, [image?.id]);

  return (
    <dialog
      ref={dialog}
      className="media-references-dialog"
      aria-labelledby="media-references-title"
      onCancel={(event) => {
        event.preventDefault();
        onClose();
      }}
    >
      <div className="media-picker-heading">
        <h2 id="media-references-title">{t('References')}</h2>
        <button
          className="icon-button"
          type="button"
          onClick={onClose}
          aria-label={t('Close references')}
        >
          <Icon name="x" />
        </button>
      </div>
      {image && (
        <div className="media-reference-image">
          <img src={image.url} alt={image.alt} />
          <strong>{image.title || image.filename}</strong>
        </div>
      )}
      {error && (
        <p className="upload-status error" role="alert">
          {t(error)}
        </p>
      )}
      {!verified && (
        <p className="media-reference-warning" role="alert">
          {t('Some references could not be checked. Deletion remains locked.')}
        </p>
      )}
      <ul className="media-reference-list" aria-busy={busy}>
        {items.map((reference) => (
          <li key={reference.id}>
            <div>
              <span>{t(reference.type)}</span>
              <strong>
                {reference.href ? (
                  <a href={reference.href} onClick={onClose}>
                    {reference.title}
                  </a>
                ) : (
                  reference.title
                )}
              </strong>
              {reference.detail && <p>{reference.detail}</p>}
            </div>
            {reference.restricted ? (
              <Icon name="lock" />
            ) : reference.href ? (
              <a href={reference.href} onClick={onClose} aria-label={t('Open reference')}>
                <Icon name="arrow-up-right" />
              </a>
            ) : null}
          </li>
        ))}
      </ul>
      {!busy && !error && verified && items.length === 0 && (
        <p className="empty-state">
          {canDelete
            ? t('No references found. This image can be deleted.')
            : t('This image is in use. Refresh to view its references.')}
        </p>
      )}
      <div className="media-reference-footer">
        <button
          type="button"
          className="button button-outline"
          disabled={busy || !image}
          onClick={() => image && void load(`/admin/media/${image.id}/references`, true, image.id)}
        >
          {t('Refresh')}
        </button>
        {next && (
          <button
            type="button"
            className="button button-outline"
            disabled={busy}
            onClick={() => image && void load(next, false, image.id)}
          >
            {t('Load more')}
          </button>
        )}
        {busy && <span role="status">{t('Loading…')}</span>}
      </div>
    </dialog>
  );
}
