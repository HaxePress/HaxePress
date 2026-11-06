import { Link, usePage } from '@inertiajs/react';
import type { ReactNode } from 'react';
import {
  hasCapability,
  type ContentItem,
  type SharedProps,
  type ExtensionBlock,
} from '../../types';
import { useTranslation } from '../../i18n';
import AdminLayout from '../../layouts/AdminLayout';
import PageHead from '../../components/PageHead';
import ContentTable from '../../components/ContentTable';
import Icon from '../../components/Icon';
import Markdown from '../../components/Markdown';
import type { ActivityEntry } from './Activity';

interface CollectionCard {
  key: string;
  name: string;
  singular: string;
  admin_path: string;
  icon: string;
  items: number;
}

export default function Dashboard({
  published,
  drafts,
  scheduled,
  items,
  collections,
  collectionCards,
  activity,
  widgets,
}: {
  published: number;
  drafts: number;
  scheduled: number;
  items: ContentItem[];
  collections: number;
  collectionCards: CollectionCard[];
  activity: ActivityEntry[];
  widgets: ExtensionBlock[];
}) {
  const { t } = useTranslation();
  const { auth } = usePage<SharedProps>().props;
  const capabilities = auth?.admin.capabilities || [];
  const firstCollection = collectionCards[0];
  const stats = [
    { label: 'Published content', value: published, icon: 'file', status: 'published' },
    { label: 'Drafts', value: drafts, icon: 'edit', status: 'draft' },
    { label: 'Collections', value: collections, icon: 'layers', status: 'pages' },
    { label: 'Scheduled content', value: scheduled, icon: 'clock', status: 'scheduled' },
  ];
  return (
    <>
      <PageHead title={t('Overview')} admin />
      <div className="admin-page-heading dashboard-heading">
        <div>
          <h1>{t('Overview')}</h1>
        </div>
        <div className="package-actions">
          {hasCapability(capabilities, 'extensions') && (
            <Link className="button button-outline" href="/admin/themes/create">
              <Icon name="palette" />
              {t('Build your website')}
            </Link>
          )}
          {firstCollection && (
            <Link className="button" href={`/admin/${firstCollection.admin_path}/new`}>
              <Icon name="plus" /> {t('Create {type}', { type: t(firstCollection.singular) })}
            </Link>
          )}
        </div>
      </div>
      <section className="publication-summary" aria-label={t('Site summary')}>
        {stats.map((stat) => (
          <div className={`site-stat site-stat-${stat.status}`} key={stat.label}>
            <span className="publication-stat-label">
              <Icon name={stat.icon} /> {t(stat.label)}
            </span>
            <strong>{stat.value}</strong>
          </div>
        ))}
      </section>
      {collectionCards.length > 0 && (
        <section className="admin-card dashboard-collections">
          <div className="admin-card-heading">
            <div>
              <h2>{t('Your collections')}</h2>
              <p>{t('Each collection uses its own fields and editor features.')}</p>
            </div>
            <Link href="/admin/collections" className="text-link">
              {t('All collections')} <Icon name="arrow-right" />
            </Link>
          </div>
          <div className="collection-shortcuts">
            {collectionCards.map((type) => (
              <Link key={type.key} href={`/admin/${type.admin_path}`}>
                <Icon name={type.icon} />
                <span>
                  <strong>{t(type.name)}</strong>
                  <small>{t('Content count', { count: type.items })}</small>
                </span>
                <Icon name="chevron-right" />
              </Link>
            ))}
          </div>
        </section>
      )}
      <div className="dashboard-grid">
        <section className="admin-card recent-content-card">
          <div className="admin-card-heading">
            <div>
              <h2>{t('Recent content')}</h2>
              <p>{t('The latest changes across your collections.')}</p>
            </div>
          </div>
          {items.length ? (
            <ContentTable items={items} compact />
          ) : (
            <div className="empty-state">
              <Icon name="file" />
              <h2>{t('No content')}</h2>
              <p>{t('Choose a collection to create your first content item.')}</p>
            </div>
          )}
        </section>
        {hasCapability(capabilities, 'activity') && (
          <section className="admin-card activity-card">
            <div className="admin-card-heading">
              <h2>{t('Recent activity')}</h2>
              <Link href="/admin/activity" className="text-link">
                {t('View all')} <Icon name="arrow-right" />
              </Link>
            </div>
            <div className="dashboard-activity">
              {activity.length ? (
                activity.map((entry) => (
                  <div key={entry.id}>
                    <strong>{entry.actor}</strong>
                    <p>
                      {t(entry.action)} · {entry.label}
                    </p>
                    <small>{entry.created_at}</small>
                  </div>
                ))
              ) : (
                <p className="empty-state">{t('No activity yet.')}</p>
              )}
            </div>
          </section>
        )}
      </div>
      {widgets.length > 0 && (
        <div className="dashboard-widgets">
          {widgets.map((widget) => (
            <section className="admin-card" key={widget.id}>
              <Markdown content={widget.content} />
            </section>
          ))}
        </div>
      )}
    </>
  );
}
Dashboard.layout = (page: ReactNode) => <AdminLayout>{page}</AdminLayout>;
