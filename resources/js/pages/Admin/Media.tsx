import { useTranslation } from '../../i18n';
import { router, useForm, usePage } from '@inertiajs/react';
import { useEffect, useState, type ChangeEvent, type ReactNode } from 'react';
import AdminLayout from '../../layouts/AdminLayout';
import PageHead from '../../components/PageHead';
import Alert from '../../components/Alert';
import ConfirmDialog from '../../components/ConfirmDialog';
import Pagination from '../../components/Pagination';
import Icon from '../../components/Icon';
import MediaReferences from '../../components/MediaReferences';
import { uploadManagedImage } from '../../media';
import { errorText, type MediaImage, type PageLinks, type SharedProps } from '../../types';

interface LibraryImage extends MediaImage {
  can_delete: boolean;
  references_verified: boolean;
}

export default function Media({
  images,
  total,
  query,
  pagination,
  notice,
}: {
  images: LibraryImage[];
  total: number;
  query: string;
  pagination: PageLinks;
  notice: string;
}) {
  const { t } = useTranslation();
  const { csrfToken, errors, mediaRules } = usePage<SharedProps>().props;
  const [search, setSearch] = useState(query);
  const [selected, setSelected] = useState<MediaImage | null>(null);
  const [pending, setPending] = useState<MediaImage | null>(null);
  const [uploading, setUploading] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [references, setReferences] = useState<MediaImage | null>(null);
  const [checked, setChecked] = useState<Record<number, { canDelete: boolean; verified: boolean }>>(
    {},
  );
  useEffect(() => setChecked({}), [images]);
  const form = useForm({ title: '', alt: '' });

  async function upload(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    event.target.value = '';
    if (!file) return;
    setUploading(true);
    setError('');
    try {
      await uploadManagedImage(file, csrfToken, mediaRules);
      router.reload();
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : 'Upload failed.');
    } finally {
      setUploading(false);
    }
  }

  return (
    <>
      <PageHead title={t('Media library')} admin />
      <div className="admin-page-heading">
        <div>
          <h1>{t('Media library')}</h1>
        </div>
        <label className="button package-upload-button">
          <Icon name="upload" />
          {uploading ? t('Uploading…') : t('Upload image')}
          <input
            type="file"
            accept={mediaRules?.mimeTypes.join(',')}
            disabled={uploading}
            onChange={upload}
          />
        </label>
      </div>
      <Alert message={notice} />
      <Alert error message={error || errorText(errors.media) || errorText(form.errors)} />
      <form
        className="category-search-form extension-search"
        onSubmit={(event) => {
          event.preventDefault();
          router.get('/admin/media', { q: search });
        }}
      >
        <label className="sr-only" htmlFor="media-query">
          {t('Find an image')}
        </label>
        <input
          id="media-query"
          type="search"
          maxLength={100}
          value={search}
          onChange={(event) => setSearch(event.target.value)}
          placeholder={t('Find images by title or description…')}
        />
        <button className="button button-outline">{t('Search')}</button>
      </form>
      <div className="media-workspace">
        <section>
          <div className="media-library-grid">
            {images.map((image) => {
              const canDelete = checked[image.id]?.canDelete ?? image.can_delete;
              const verified = checked[image.id]?.verified ?? image.references_verified;
              return (
                <article
                  className={`admin-card media-card ${selected?.id === image.id ? 'selected' : ''}`}
                  key={image.id}
                >
                  <button
                    className="media-select"
                    onClick={() => {
                      setSelected(image);
                      form.setData({ title: image.title, alt: image.alt });
                    }}
                  >
                    <img src={image.url} alt={image.alt} loading="lazy" />
                    <strong>{image.title || image.filename}</strong>
                    <span>
                      {image.width} × {image.height} · {Math.ceil(image.size / 1024)} {t('KB')}
                    </span>
                  </button>
                  <div className="media-card-actions">
                    {!canDelete ? (
                      <button
                        type="button"
                        className="button button-outline"
                        onClick={() => setReferences(image)}
                      >
                        <Icon name="link" /> {t('References')}
                      </button>
                    ) : (
                      <span className="field-help">{t('Not in use')}</span>
                    )}
                    <button
                      type="button"
                      className="icon-button danger"
                      disabled={busy || !canDelete}
                      title={
                        !verified
                          ? t('References could not be verified')
                          : !canDelete
                            ? t('Image in use')
                            : t('Delete')
                      }
                      aria-label={
                        !canDelete
                          ? t('Deletion locked for {name}', { name: image.title })
                          : t('Delete {name}', { name: image.title })
                      }
                      onClick={() => canDelete && setPending(image)}
                    >
                      <Icon name={canDelete ? 'trash' : 'lock'} />
                    </button>
                  </div>
                </article>
              );
            })}
          </div>
          {images.length === 0 && (
            <section className="admin-card empty-state">
              <Icon name="image" />
              <h2>{t('No images')}</h2>
              <p>{t('Upload JPEG, PNG or GIF images up to 5 MB and 20 megapixels.')}</p>
            </section>
          )}
          <Pagination links={pagination} count={images.length} noun={t('images')} />
        </section>
        {selected && (
          <aside className="admin-card settings-card media-details">
            <img src={selected.url} alt={selected.alt} />
            <h2>{t('Image details')}</h2>
            <form
              onSubmit={(event) => {
                event.preventDefault();
                form.transform((values) => ({ ...values, _token: csrfToken }));
                form.post(`/admin/media/${selected.id}/save`, {
                  preserveScroll: true,
                  onSuccess: () => setSelected(null),
                });
              }}
            >
              <label htmlFor="media-title">{t('Title')}</label>
              <input
                id="media-title"
                value={form.data.title}
                maxLength={180}
                onChange={(event) => form.setData('title', event.target.value)}
              />
              <label htmlFor="media-alt">{t('Image description')}</label>
              <textarea
                id="media-alt"
                rows={4}
                value={form.data.alt}
                maxLength={500}
                onChange={(event) => form.setData('alt', event.target.value)}
              />
              <p className="field-help">
                {t('Describe the image for readers using assistive technology.')}
              </p>
              <button className="button" disabled={form.processing}>
                {form.processing ? t('Saving…') : t('Save image details')}
              </button>
            </form>
          </aside>
        )}
      </div>
      <p className="field-help">
        {total}{' '}
        {t(
          'images. Referenced images are protected, including those in revisions and working copies.',
        )}
      </p>
      <ConfirmDialog
        open={pending !== null}
        busy={busy}
        message={`Delete “${pending?.title || ''}”? This removes the uploaded file.`}
        onCancel={() => setPending(null)}
        onConfirm={() => {
          if (!pending) return;
          router.post(
            `/admin/media/${pending.id}/delete`,
            { _token: csrfToken },
            {
              preserveScroll: true,
              onStart: () => setBusy(true),
              onFinish: () => {
                setBusy(false);
                setPending(null);
                setSelected(null);
              },
            },
          );
        }}
      />
      <MediaReferences
        image={references}
        onClose={() => setReferences(null)}
        onChecked={(id, canDelete, verified) =>
          setChecked((current) => ({ ...current, [id]: { canDelete, verified } }))
        }
      />
    </>
  );
}
Media.layout = (page: ReactNode) => <AdminLayout>{page}</AdminLayout>;
