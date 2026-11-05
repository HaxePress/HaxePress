import { useTranslation } from '../i18n';
import { useEffect, useRef, useState } from 'react';
import type { MediaImage, PageLinks } from '../types';

export default function MediaPicker({
  open,
  onClose,
  onPick,
  idPrefix = '',
  onUpload,
  uploading = false,
  libraryUrl = '/admin/media',
  title = 'Choose an image',
  description = '',
  emptyMessage = 'No matching images. Upload an image to the media library.',
  onRemove,
  protectedUrls,
}: {
  open: boolean;
  onClose: () => void;
  onPick: (image: MediaImage) => void;
  idPrefix?: string;
  onUpload?: (file: File) => void;
  uploading?: boolean;
  libraryUrl?: string;
  title?: string;
  description?: string;
  emptyMessage?: string;
  onRemove?: (image: MediaImage) => Promise<void>;
  protectedUrls?: Set<string>;
}) {
  const { t } = useTranslation();
  const dialog = useRef<HTMLDialogElement>(null);
  const [query, setQuery] = useState('');
  const [images, setImages] = useState<MediaImage[]>([]);
  const [links, setLinks] = useState<PageLinks | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const abort = useRef<AbortController | null>(null);
  const currentPath = useRef('');
  async function remove(image: MediaImage) {
    if (!onRemove) return;
    setBusy(true);
    setError('');
    try {
      await onRemove(image);
      await load(currentPath.current);
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : 'The image could not be deleted.');
    } finally {
      setBusy(false);
    }
  }

  async function load(path: string) {
    currentPath.current = path;
    abort.current?.abort();
    const controller = new AbortController();
    abort.current = controller;
    setBusy(true);
    setError('');
    try {
      const url = new URL(path, window.location.origin);
      url.searchParams.set('format', 'json');
      const response = await fetch(url, {
        headers: { Accept: 'application/json' },
        signal: controller.signal,
      });
      if (!response.ok) throw new Error('Images could not be loaded.');
      const data: { images: MediaImage[]; pagination: PageLinks } = await response.json();
      setImages(data.images);
      setLinks(data.pagination);
    } catch (failure) {
      if (!(failure instanceof Error) || failure.name !== 'AbortError')
        setError('Images could not be loaded. Try again.');
    } finally {
      if (!controller.signal.aborted) setBusy(false);
    }
  }
  useEffect(() => {
    if (open && !dialog.current?.open) dialog.current?.showModal();
    if (!open && dialog.current?.open) dialog.current.close();
  }, [open]);
  useEffect(() => {
    if (!open) return;
    const timeout = setTimeout(
      () => void load(libraryUrl + '?q=' + encodeURIComponent(query)),
      200,
    );
    return () => {
      clearTimeout(timeout);
      abort.current?.abort();
    };
  }, [open, query, libraryUrl]);

  return (
    <dialog
      ref={dialog}
      className="media-picker-dialog"
      aria-labelledby={idPrefix + 'media-picker-title'}
      onCancel={(event) => {
        event.preventDefault();
        onClose();
      }}
    >
      <div className="media-picker-heading">
        <h2 id={idPrefix + 'media-picker-title'}>{t(title)}</h2>
        <button
          className="icon-button"
          type="button"
          onClick={onClose}
          aria-label={t('Close image library')}
        >
          ×
        </button>
      </div>
      {description && <p className="field-help">{t(description)}</p>}
      <label className="sr-only" htmlFor={idPrefix + 'picker-query'}>
        {t('Search images')}
      </label>
      <input
        id={idPrefix + 'picker-query'}
        type="search"
        value={query}
        maxLength={100}
        placeholder={t('Find an image…')}
        onChange={(event) => setQuery(event.target.value)}
      />
      {error && <p role="alert">{t(error)}</p>}
      <div className="media-picker-grid" aria-busy={busy}>
        {images.map((image) => (
          <div key={image.id} className="media-picker-card">
            <button
              type="button"
              onClick={() => {
                onPick(image);
                onClose();
              }}
            >
              <img src={image.url} alt={image.alt} loading="lazy" />
              <span>{image.title || image.filename}</span>
            </button>
            {onRemove && (
              <button
                className="theme-image-remove"
                type="button"
                disabled={busy || uploading || image.in_use || protectedUrls?.has(image.url)}
                onClick={() => void remove(image)}
              >
                {t(
                  image.in_use || protectedUrls?.has(image.url)
                    ? 'Used by this theme'
                    : 'Delete image',
                )}
              </button>
            )}
          </div>
        ))}
      </div>
      {!busy && images.length === 0 && <p className="empty-state">{t(emptyMessage)}</p>}
      <div className="package-actions">
        {onUpload && (
          <label className="button button-outline package-upload-button">
            {t(uploading ? 'Uploading…' : 'Upload image')}
            <input
              type="file"
              accept="image/jpeg,image/png,image/webp,image/gif"
              disabled={uploading}
              onChange={(event) => {
                const file = event.target.files?.[0];
                event.target.value = '';
                if (file) onUpload(file);
              }}
            />
          </label>
        )}

        <button
          className="button button-outline"
          type="button"
          disabled={!links?.previous || busy}
          onClick={() => links?.previous && void load(links.previous)}
        >
          {t('Previous')}
        </button>
        <button
          className="button button-outline"
          type="button"
          disabled={!links?.next || busy}
          onClick={() => links?.next && void load(links.next)}
        >
          {t('Next')}
        </button>
        {busy && <span role="status">{t('Loading…')}</span>}
      </div>
    </dialog>
  );
}
