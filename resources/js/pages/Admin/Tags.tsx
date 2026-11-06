import { useTranslation } from '../../i18n';
import { Link, router, useForm, usePage } from '@inertiajs/react';
import { useEffect, useRef, useState, type ReactNode } from 'react';
import AdminLayout from '../../layouts/AdminLayout';
import PageHead from '../../components/PageHead';
import Alert from '../../components/Alert';
import ConfirmDialog from '../../components/ConfirmDialog';
import Pagination from '../../components/Pagination';
import Icon from '../../components/Icon';
import { errorText, type Tag, type PageLinks, type SharedProps } from '../../types';

export default function Tags({
  tags,
  total,
  query,
  pagination,
  notice,
}: {
  tags: Tag[];
  total: number;
  query: string;
  pagination: PageLinks;
  notice: string;
}) {
  const { t } = useTranslation();
  const { csrfToken, errors } = usePage<SharedProps>().props;
  const empty = { id: '', name: '', slug: '', description: '' };
  const form = useForm(empty);
  const [search, setSearch] = useState(query);
  const [pending, setPending] = useState<Tag | null>(null);
  const [deleting, setDeleting] = useState(false);
  const [customSlug, setCustomSlug] = useState(false);
  const nameInput = useRef<HTMLInputElement>(null);
  useEffect(() => setSearch(query), [query]);
  const editing = Boolean(form.data.id);
  const busy = form.processing || deleting;

  function reset() {
    form.setData(empty);
    form.clearErrors();
    setCustomSlug(false);
  }
  function edit(tag: Tag) {
    form.setData({
      id: String(tag.id),
      name: tag.name,
      slug: tag.slug,
      description: tag.description,
    });
    setCustomSlug(true);
    form.clearErrors();
    nameInput.current?.focus();
  }

  return (
    <>
      <PageHead title={t('Tags')} admin />
      <div className="admin-page-heading">
        <div>
          <h1>{t('Tags')}</h1>
        </div>
      </div>
      <Alert message={notice} />
      <Alert error message={errorText(form.errors) || errorText(errors.tag)} />
      <div className="categories-grid">
        <section className="admin-card category-collection">
          <div className="admin-card-heading">
            <div>
              <h2>
                {t('Your tags')} <span className="count-badge">{total}</span>
              </h2>
              <p>
                {t('Tag archives show published content. Usage counts include drafts and pages.')}
              </p>
            </div>
          </div>
          <form
            className="category-search-form"
            onSubmit={(event) => {
              event.preventDefault();
              router.get('/admin/tags', { q: search }, { preserveState: true });
            }}
          >
            <label className="sr-only" htmlFor="tags-query">
              {t('Find a tag')}
            </label>
            <input
              id="tags-query"
              type="search"
              value={search}
              onChange={(event) => setSearch(event.target.value)}
              placeholder={t('Find a tag by name…')}
              maxLength={80}
            />
            <button className="button button-outline">{t('Search')}</button>
          </form>
          {tags.length > 0 ? (
            <ul className="category-list">
              {tags.map((tag) => (
                <li key={tag.id} className={form.data.id === String(tag.id) ? 'editing' : ''}>
                  <div className="category-details">
                    <strong>{tag.name}</strong>
                    <span>
                      {tag.items || 0} {t('content items')}{' '}
                      <Link href={`/tags/${tag.slug}`} className="tag-archive-link">
                        {t('View archive')}
                      </Link>
                    </span>
                  </div>
                  <div className="category-actions">
                    <button
                      className="icon-button"
                      aria-label={`Edit ${tag.name}`}
                      onClick={() => edit(tag)}
                      disabled={busy}
                    >
                      <Icon name="edit" />
                    </button>
                    <button
                      className="icon-button danger"
                      aria-label={`Delete ${tag.name}`}
                      onClick={() => setPending(tag)}
                      disabled={busy}
                    >
                      <Icon name="trash" />
                    </button>
                  </div>
                </li>
              ))}
            </ul>
          ) : (
            <div className="empty-state">
              <Icon name="grid" />
              <h2>{t('Ideas that belong together.')}</h2>
              <p>{t('Create a tag, then add it to content in the editor.')}</p>
            </div>
          )}
          <Pagination links={pagination} count={tags.length} noun={t('tags')} />
        </section>
        <section className="admin-card settings-card category-form">
          <h2>{editing ? t('Edit tag') : t('Add a tag')}</h2>
          <p>{t('Names appear in the editor and on your public tag archives.')}</p>
          <form
            onSubmit={(event) => {
              event.preventDefault();
              form.transform((data) => ({ ...data, _token: csrfToken }));
              form.post('/admin/tags/save', { preserveScroll: true, onSuccess: reset });
            }}
          >
            <label htmlFor="tag-name">{t('Tag name')}</label>
            <input
              ref={nameInput}
              id="tag-name"
              value={form.data.name}
              required
              maxLength={80}
              placeholder={t('For example, Slow living')}
              disabled={busy}
              onChange={(event) => {
                const name = event.target.value;
                const slug = name
                  .toLowerCase()
                  .normalize('NFKD')
                  .replace(/[\u0300-\u036f]/g, '')
                  .replace(/[^a-z0-9]+/g, '-')
                  .replace(/^-|-$/g, '');
                form.setData((previous) => ({ ...previous, name, ...(!customSlug && { slug }) }));
              }}
            />
            <label htmlFor="tag-slug">{t('URL slug')}</label>
            <input
              id="tag-slug"
              value={form.data.slug}
              required
              maxLength={120}
              disabled={busy}
              onChange={(event) => {
                setCustomSlug(true);
                form.setData('slug', event.target.value);
              }}
            />
            <p className="field-help">/tag/{form.data.slug || t('your-tag')}</p>
            <label htmlFor="tag-description">{t('Description')}</label>
            <textarea
              id="tag-description"
              rows={4}
              maxLength={500}
              value={form.data.description}
              disabled={busy}
              onChange={(event) => form.setData('description', event.target.value)}
            />
            <div className="category-form-actions">
              <button className="button" disabled={busy}>
                {form.processing ? t('Saving…') : editing ? t('Save changes') : t('Add tag')}
              </button>
              {editing && (
                <button
                  className="button button-outline"
                  type="button"
                  onClick={reset}
                  disabled={busy}
                >
                  {t('Cancel')}
                </button>
              )}
            </div>
          </form>
        </section>
      </div>
      <ConfirmDialog
        open={pending !== null}
        message={`Delete “${pending?.name || ''}”? Its content assignments will be removed. Your content will be kept.`}
        busy={deleting}
        onCancel={() => setPending(null)}
        onConfirm={() => {
          if (!pending) return;
          router.post(
            `/admin/tags/${pending.id}/delete`,
            { _token: csrfToken },
            {
              preserveScroll: true,
              onStart: () => setDeleting(true),
              onFinish: () => {
                setPending(null);
                setDeleting(false);
              },
              onSuccess: reset,
            },
          );
        }}
      />
    </>
  );
}
Tags.layout = (page: ReactNode) => <AdminLayout>{page}</AdminLayout>;
