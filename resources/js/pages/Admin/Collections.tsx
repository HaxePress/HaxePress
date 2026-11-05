import { Link, router } from '@inertiajs/react';
import { useEffect, useState, type ReactNode } from 'react';
import AdminLayout from '../../layouts/AdminLayout';
import PageHead from '../../components/PageHead';
import Pagination from '../../components/Pagination';
import Alert from '../../components/Alert';
import Icon from '../../components/Icon';
import type { PageLinks } from '../../types';
import { useTranslation } from '../../i18n';

interface CollectionSummary {
  key: string;
  name: string;
  singular: string;
  icon: string;
  admin_path: string;
  public_path: string;
  public_visible: number;
  enabled: number;
  system: number;
  owner: string;
  owner_active: number;
  items: number;
}

export default function Collections({
  collections,
  pagination,
  query,
  canManage,
  notice,
}: {
  collections: CollectionSummary[];
  pagination: PageLinks;
  query: string;
  canManage: boolean;
  notice: string;
}) {
  const { t } = useTranslation();
  const [search, setSearch] = useState(query);
  useEffect(() => setSearch(query), [query]);
  return (
    <>
      <PageHead title={t('All collections')} admin />
      <div className="admin-page-heading">
        <div>
          <h1>{t('All collections')}</h1>
        </div>
        {canManage && (
          <Link className="button" href="/admin/content-types/new">
            <Icon name="plus" /> {t('New collection')}
          </Link>
        )}
      </div>
      <Alert
        message={notice === 'removed' ? t('The empty collection definition has been removed.') : ''}
      />
      <section className="admin-card">
        <div className="admin-card-heading">
          <h2>{t('Content types')}</h2>
          <form
            className="admin-search"
            action="/admin/collections"
            method="get"
            onSubmit={(event) => {
              event.preventDefault();
              router.get('/admin/collections', { q: search }, { preserveState: true });
            }}
          >
            <Icon name="search" />
            <label className="sr-only" htmlFor="collection-search">
              {t('Search collections')}
            </label>
            <input
              id="collection-search"
              name="q"
              type="search"
              value={search}
              maxLength={100}
              placeholder={t('Search collections')}
              onChange={(event) => setSearch(event.target.value)}
            />
          </form>
        </div>
        <div className="table-scroll">
          <table className="content-table">
            <thead>
              <tr>
                <th>{t('Collection')}</th>
                <th>{t('Content')}</th>
                <th>{t('Availability')}</th>
                <th>{t('Public path')}</th>
                <th>
                  <span className="sr-only">{t('Actions')}</span>
                </th>
              </tr>
            </thead>
            <tbody>
              {collections.map((type) => {
                const active = type.enabled === 1 && (!type.owner || type.owner_active > 0);
                return (
                  <tr key={type.key}>
                    <td>
                      <div className="table-content">
                        <span className="table-image-placeholder">
                          <Icon name={type.icon} />
                        </span>
                        <span>
                          <strong>
                            {active ? (
                              <Link href={'/admin/' + type.admin_path}>{t(type.name)}</Link>
                            ) : (
                              t(type.name)
                            )}
                          </strong>
                          <small>
                            {type.key} {type.owner && <span>{type.owner}</span>}
                          </small>
                        </span>
                      </div>
                    </td>
                    <td>{type.items}</td>
                    <td>
                      <span className={'status ' + (active ? 'published' : 'draft')}>
                        {!active ? t('Disabled') : type.public_visible ? t('Public') : t('Private')}
                      </span>
                    </td>
                    <td>
                      /{type.public_path}/{'{slug}'}
                    </td>
                    <td>
                      <div className="table-actions">
                        {active && (
                          <Link
                            className="button button-outline"
                            href={'/admin/' + type.admin_path}
                          >
                            {t('Open collection')}
                          </Link>
                        )}
                        {canManage && (
                          <Link
                            className="icon-button"
                            href={'/admin/content-types/' + type.key + '/edit'}
                            aria-label={t('Configure {name}', { name: type.name })}
                          >
                            <Icon name="settings" />
                          </Link>
                        )}
                      </div>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
        {collections.length === 0 && (
          <div className="empty-state">
            <Icon name="layers" />
            <h2>{t('No matching collections')}</h2>
            <p>{t('Try another name or create a content type for your site.')}</p>
          </div>
        )}
      </section>
      <Pagination links={pagination} count={collections.length} noun={t('collections')} />
    </>
  );
}
Collections.layout = (page: ReactNode) => <AdminLayout>{page}</AdminLayout>;
