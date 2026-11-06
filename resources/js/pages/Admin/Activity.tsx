import { useTranslation } from '../../i18n';
import { router } from '@inertiajs/react';
import type { ReactNode } from 'react';
import AdminLayout from '../../layouts/AdminLayout';
import PageHead from '../../components/PageHead';
import Pagination from '../../components/Pagination';
import Icon from '../../components/Icon';
import type { PageLinks } from '../../types';

export interface ActivityEntry {
  id: number;
  actor: string;
  action: string;
  entity: string;
  entity_id: number;
  label: string;
  created_at: string;
}
export default function Activity({
  entries,
  entity,
  total,
  pagination,
}: {
  entries: ActivityEntry[];
  entity: string;
  total: number;
  pagination: PageLinks;
}) {
  const { t } = useTranslation();
  return (
    <>
      <PageHead title={t('Activity')} admin />
      <div className="admin-page-heading">
        <div>
          <h1>{t('Activity')}</h1>
        </div>
        <label className="activity-filter">
          {t('Show')}
          <select
            value={entity}
            onChange={(event) => router.get('/admin/activity', { entity: event.target.value })}
          >
            <option value="">{t('All activity')}</option>
            {[
              'entry',
              'page',
              'tag',
              'category',
              'media',
              'plugin',
              'theme',
              'navigation',
              'member',
            ].map((kind) => (
              <option key={kind} value={kind}>
                {t(`${kind.charAt(0).toUpperCase()}${kind.slice(1)}`)}
              </option>
            ))}
          </select>
        </label>
      </div>
      <section className="admin-card activity-card">
        <div className="admin-card-heading">
          <h2>
            {t('Recent changes')} <span className="count-badge">{total}</span>
          </h2>
        </div>
        {entries.length ? (
          <ol className="activity-list">
            {entries.map((entry) => (
              <li key={entry.id}>
                <span className="activity-marker">
                  <Icon name="clock" />
                </span>
                <div>
                  <p>
                    <strong>{entry.actor}</strong> {t(`activity.${entry.action}`)}{' '}
                    <span className="activity-kind">{t(entry.entity)}</span>
                  </p>
                  <span>{entry.label || t('Untitled')}</span>
                </div>
                <time dateTime={entry.created_at.replace(' ', 'T')}>{entry.created_at}</time>
              </li>
            ))}
          </ol>
        ) : (
          <div className="empty-state">
            <Icon name="clock" />
            <h2>{t('No activity')}</h2>
            <p>{t('Changes will appear here as your team works.')}</p>
          </div>
        )}
        <Pagination links={pagination} count={entries.length} noun={t('changes')} />
      </section>
    </>
  );
}
Activity.layout = (page: ReactNode) => <AdminLayout>{page}</AdminLayout>;
