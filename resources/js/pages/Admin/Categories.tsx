import { useTranslation } from '../../i18n';
import { router, useForm, usePage } from '@inertiajs/react';
import { useEffect, useRef, useState, type ReactNode } from 'react';
import AdminLayout from '../../layouts/AdminLayout';
import PageHead from '../../components/PageHead';
import Alert from '../../components/Alert';
import ConfirmDialog from '../../components/ConfirmDialog';
import Icon from '../../components/Icon';
import Pagination from '../../components/Pagination';
import { errorText, type Category, type PageLinks, type SharedProps } from '../../types';

type CategoryForm = { id: string; name: string };

export default function Categories({
  categoryList,
  notice,
  categoryForm,
  query,
  total,
  pagination,
}: {
  categoryList: Category[];
  notice: string;
  categoryForm: CategoryForm;
  query: string;
  total: number;
  pagination: PageLinks;
}) {
  const { t } = useTranslation();
  const { csrfToken, errors } = usePage<SharedProps>().props;
  const form = useForm<CategoryForm>(categoryForm);
  const [search, setSearch] = useState(query);
  useEffect(() => setSearch(query), [query]);
  const nameInput = useRef<HTMLInputElement>(null);
  const [pending, setPending] = useState<Category | null>(null);
  const [deleting, setDeleting] = useState(false);
  const editing = Boolean(form.data.id);
  const busy = form.processing || deleting;

  function reset() {
    form.setData({ id: '', name: '' });
    form.clearErrors();
  }

  function edit(category: Category) {
    form.clearErrors();
    form.setData({ id: String(category.id), name: category.name });
    nameInput.current?.focus();
  }

  return (
    <>
      <PageHead title={t('Categories')} admin />
      <div className="admin-page-heading">
        <div>
          <h1>{t('Categories')}</h1>
        </div>
      </div>
      <Alert message={notice} />
      <Alert error message={errorText(form.errors) || errorText(errors?.category)} />
      <div className="categories-grid">
        <section className="admin-card category-collection" aria-labelledby="category-list-title">
          <div className="admin-card-heading">
            <div>
              <h2 id="category-list-title">
                {t('Your categories')} <span className="count-badge">{total}</span>
              </h2>
              <p>
                {t('Content counts include drafts. Move content before deleting their category.')}
              </p>
            </div>
          </div>
          <form
            className="category-search-form"
            action="/admin/categories"
            method="get"
            onSubmit={(event) => {
              event.preventDefault();
              router.get('/admin/categories', { q: search }, { preserveState: true });
            }}
          >
            <label className="sr-only" htmlFor="category-query">
              {t('Find a category')}
            </label>
            <input
              id="category-query"
              name="q"
              type="search"
              maxLength={80}
              value={search}
              onChange={(event) => setSearch(event.target.value)}
              placeholder={t('Find a category by name…')}
            />
            <button className="button button-outline" type="submit">
              {t('Search')}
            </button>
          </form>
          {categoryList.length ? (
            <ul className="category-list">
              {categoryList.map((category) => (
                <li
                  key={category.id}
                  className={form.data.id === String(category.id) ? 'editing' : ''}
                >
                  <div className="category-details">
                    <strong>{category.name}</strong>
                    <span>
                      {category.items}{' '}
                      {category.items === 1 ? t('content item') : t('content items')}
                    </span>
                  </div>
                  <div className="category-actions">
                    <button
                      type="button"
                      className="icon-button"
                      aria-label={'Rename ' + category.name}
                      disabled={busy}
                      onClick={() => edit(category)}
                    >
                      <Icon name="edit" />
                    </button>
                    <button
                      type="button"
                      className="icon-button danger"
                      aria-label={'Delete ' + category.name}
                      disabled={busy || category.items > 0}
                      title={
                        category.items > 0
                          ? t('Move these content to another category before deleting.')
                          : t('Delete category')
                      }
                      onClick={() => setPending(category)}
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
              <h2>{t('No categories')}</h2>
              <p>{t('Add your first category to start organizing content.')}</p>
            </div>
          )}
          <Pagination links={pagination} count={categoryList.length} noun={t('categories')} />
        </section>
        <section
          className="admin-card settings-card category-form"
          aria-labelledby="category-form-title"
        >
          <h2 id="category-form-title">{editing ? t('Rename category') : t('Add a category')}</h2>
          <p>
            {editing
              ? t('The new name will appear on all content in this category.')
              : t('New categories appear in the content item editor and site filters.')}
          </p>
          <form
            action="/admin/categories/save"
            method="post"
            onSubmit={(event) => {
              event.preventDefault();
              form.transform((data) => ({ ...data, _token: csrfToken }));
              form.post('/admin/categories/save', { preserveScroll: true, onSuccess: reset });
            }}
          >
            <input type="hidden" name="_token" value={csrfToken || ''} />
            <input type="hidden" name="id" value={form.data.id} />
            <label htmlFor="category-name">{t('Category name')}</label>
            <input
              ref={nameInput}
              id="category-name"
              name="name"
              required
              maxLength={80}
              placeholder={t('For example, Food & drink')}
              value={form.data.name}
              disabled={busy}
              onChange={(event) => form.setData('name', event.target.value)}
            />
            <p className="field-help">{t('Choose a distinct name, up to 80 characters.')}</p>
            <div className="category-form-actions">
              <button className="button" type="submit" disabled={busy}>
                <Icon name={editing ? 'check' : 'plus'} />
                {form.processing ? t('Saving…') : editing ? t('Save changes') : t('Add category')}
              </button>
              {editing && (
                <button
                  className="button button-outline"
                  type="button"
                  disabled={busy}
                  onClick={reset}
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
        message={'Delete “' + (pending?.name || '') + '”? This category has no content.'}
        busy={deleting}
        onCancel={() => setPending(null)}
        onConfirm={() => {
          if (!pending) return;
          router.post(
            '/admin/categories/' + pending.id + '/delete',
            { _token: csrfToken },
            {
              preserveScroll: true,
              onStart: () => setDeleting(true),
              onSuccess: () => {
                if (form.data.id === String(pending.id)) reset();
              },
              onFinish: () => {
                setPending(null);
                setDeleting(false);
              },
            },
          );
        }}
      />
    </>
  );
}

Categories.layout = (page: ReactNode) => <AdminLayout>{page}</AdminLayout>;
