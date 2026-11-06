import { Link, router } from '@inertiajs/react';
import { useEffect, useState, type ReactNode } from 'react';
import AdminLayout from '../../layouts/AdminLayout';
import PageHead from '../../components/PageHead';
import Pagination from '../../components/Pagination';
import Icon from '../../components/Icon';
import Alert from '../../components/Alert';
import type { PageLinks } from '../../types';
import { useTranslation } from '../../i18n';

export interface RoleDefinition {
  key: string;
  name: string;
  description: string;
  enabled: number;
  system: number;
  owner: string;
}

export default function Roles({
  roles,
  query,
  pagination,
  notice,
}: {
  roles: RoleDefinition[];
  query: string;
  pagination: PageLinks;
  notice: string;
}) {
  const { t } = useTranslation();
  const [search, setSearch] = useState(query);
  useEffect(() => setSearch(query), [query]);
  return (
    <>
      <PageHead title={t('Roles')} admin />
      <div className="admin-page-heading">
        <div>
          <h1>{t('Roles')}</h1>
        </div>
        <Link className="button" href="/admin/roles/new">
          <Icon name="plus" /> {t('New role')}
        </Link>
      </div>
      <Alert message={notice === 'removed' ? t('The unused role has been removed.') : ''} />
      <section className="admin-card">
        <div className="admin-card-heading">
          <h2>{t('Access roles')}</h2>
          <form
            className="admin-search"
            method="get"
            action="/admin/roles"
            onSubmit={(event) => {
              event.preventDefault();
              router.get('/admin/roles', { q: search }, { preserveState: true });
            }}
          >
            <Icon name="search" />
            <label className="sr-only" htmlFor="role-search">
              {t('Search roles')}
            </label>
            <input
              id="role-search"
              name="q"
              value={search}
              maxLength={100}
              onChange={(event) => setSearch(event.target.value)}
              placeholder={t('Search roles')}
            />
          </form>
        </div>
        <div className="table-scroll">
          <table className="content-table">
            <thead>
              <tr>
                <th>{t('Role')}</th>
                <th>{t('Description')}</th>
                <th>{t('Status')}</th>
                <th>
                  <span className="sr-only">{t('Actions')}</span>
                </th>
              </tr>
            </thead>
            <tbody>
              {roles.map((role) => (
                <tr key={role.key}>
                  <td>
                    <strong>
                      <Link href={`/admin/roles/${role.key}/edit`}>{t(role.name)}</Link>
                    </strong>
                    <small className="field-help"> {role.key}</small>
                  </td>
                  <td>{role.description}</td>
                  <td>
                    <span className={`status ${role.enabled ? 'published' : 'draft'}`}>
                      {t(role.enabled ? 'Enabled' : 'Disabled')}
                    </span>
                  </td>
                  <td>
                    <Link
                      className="icon-button"
                      href={`/admin/roles/${role.key}/edit`}
                      aria-label={t('Edit {name}', { name: role.name })}
                    >
                      <Icon name="edit" />
                    </Link>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
      <Pagination links={pagination} count={roles.length} noun={t('roles')} />
    </>
  );
}
Roles.layout = (page: ReactNode) => <AdminLayout>{page}</AdminLayout>;
