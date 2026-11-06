import { useTranslation } from '../../i18n';
import { router, usePage } from '@inertiajs/react';
import { useState, type ReactNode } from 'react';
import AdminLayout from '../../layouts/AdminLayout';
import PageHead from '../../components/PageHead';
import Pagination from '../../components/Pagination';
import ConfirmDialog from '../../components/ConfirmDialog';
import Icon from '../../components/Icon';
import type { PageLinks, SharedProps } from '../../types';

interface PluginTable {
  namespace?: string;
  title: string;
  description: string;
  total: number;
  columns: { key: string; label: string }[];
  rows: ({ id: number | string } & Record<string, unknown>)[];
  actions: { href: string; label: string; download?: boolean }[];
  rowAction?: { label: string; path: string; confirm: string };
  pagination: PageLinks;
  noun: string;
}
export default function PluginPage({ pluginPage: page }: { pluginPage: PluginTable }) {
  const { t } = useTranslation(page.namespace);
  const { csrfToken } = usePage<SharedProps>().props;
  const [pending, setPending] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  return (
    <>
      <PageHead title={t(page.title)} admin />
      <div className="admin-page-heading">
        <div>
          <h1>{t(page.title)}</h1>
          <p>{t(page.description)}</p>
        </div>
        <div>
          {page.actions.map((action) => (
            <a
              className="button button-outline"
              key={action.href}
              href={action.href}
              download={action.download}
            >
              <Icon name="download" />
              {t(action.label)}
            </a>
          ))}
        </div>
      </div>
      <section className="admin-card">
        <div className="admin-card-heading">
          <h2>
            {t(page.title)} <span className="count-badge">{page.total}</span>
          </h2>
        </div>
        {page.rows.length ? (
          <div className="table-scroll">
            <table>
              <thead>
                <tr>
                  {page.columns.map((column) => (
                    <th key={column.key}>{t(column.label)}</th>
                  ))}
                  {page.rowAction && (
                    <th>
                      <span className="sr-only">{t('Actions')}</span>
                    </th>
                  )}
                </tr>
              </thead>
              <tbody>
                {page.rows.map((row) => {
                  const actionPath =
                    page.rowAction?.path.replace('{id}', encodeURIComponent(String(row.id))) || '';
                  return (
                    <tr key={row.id}>
                      {page.columns.map((column, index) => (
                        <td key={column.key}>
                          {index === 0 ? (
                            <strong>{String(row[column.key] ?? '')}</strong>
                          ) : (
                            String(row[column.key] ?? '')
                          )}
                        </td>
                      ))}
                      {page.rowAction && (
                        <td>
                          <form
                            action={actionPath}
                            method="post"
                            onSubmit={(event) => {
                              event.preventDefault();
                              setPending(actionPath);
                            }}
                          >
                            <input type="hidden" name="_token" value={csrfToken || ''} />
                            <button
                              className="icon-button danger"
                              aria-label={`${t(page.rowAction.label)} ${String(row[page.columns[0].key])}`}
                            >
                              <Icon name="trash" />
                            </button>
                          </form>
                        </td>
                      )}
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        ) : (
          <div className="empty-state">
            <Icon name="users" />
            <h2>{t('No {items} yet.', { items: t(page.noun) })}</h2>
            <p>{t('New entries will appear here.')}</p>
          </div>
        )}
        <Pagination links={page.pagination} count={page.rows.length} noun={t(page.noun)} />
      </section>
      <ConfirmDialog
        open={pending !== null}
        message={t(page.rowAction?.confirm || 'Continue?')}
        busy={busy}
        onCancel={() => setPending(null)}
        onConfirm={() => {
          if (!pending) return;
          router.post(
            pending,
            { _token: csrfToken },
            {
              preserveScroll: true,
              onStart: () => setBusy(true),
              onFinish: () => {
                setBusy(false);
                setPending(null);
              },
            },
          );
        }}
      />
    </>
  );
}
PluginPage.layout = (page: ReactNode) => <AdminLayout>{page}</AdminLayout>;
