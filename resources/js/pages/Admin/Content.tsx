import { useTranslation } from '../../i18n';
import { Link, router } from '@inertiajs/react';
import { useEffect, useState, type ReactNode } from 'react';
import AdminLayout from '../../layouts/AdminLayout';
import PageHead from '../../components/PageHead';
import ContentTable from '../../components/ContentTable';
import Icon from '../../components/Icon';
import Alert from '../../components/Alert';
import Pagination from '../../components/Pagination';
import type { PageLinks, ContentItem } from '../../types';
import { collectionLabel, type ContentTypeDefinition } from '../../content';

export default function Content({
  items,
  total,
  published,
  drafts,
  query,
  status,
  notice,
  pagination,
  contentType,
  scheduled = 0,
  trash = 0,
  workingDrafts = [],
}: {
  items: ContentItem[];
  total: number;
  published: number;
  drafts: number;
  query: string;
  status: string;
  notice: string;
  pagination: PageLinks;
  contentType: ContentTypeDefinition;
  scheduled?: number;
  trash?: number;
  workingDrafts?: { key: string; title: string; updated_at: string }[];
}) {
  const { t } = useTranslation();
  const base = contentType.adminBase;
  const collection = t(contentType.name);
  const [search, setSearch] = useState(query);
  useEffect(() => setSearch(query), [query]);
  return (
    <>
      <PageHead title={collection} admin />
      <div className="admin-page-heading">
        <div>
          <h1>{collection}</h1>
          {(contentType.labels.description || contentType.description) && (
            <p>{t(contentType.labels.description || contentType.description)}</p>
          )}
        </div>
        <Link className="button" href={`${base}/new`}>
          <Icon name="plus" /> {collectionLabel(contentType, 'create', t)}
        </Link>
      </div>
      <Alert message={notice} />
      {workingDrafts.length > 0 && (
        <section className="admin-card working-drafts">
          <h2>{t('Your new working copies')}</h2>
          <p>{t('Resume content that has not been saved to the collection yet.')}</p>
          {workingDrafts.map((draft) => (
            <Link key={draft.key} href={`${base}/new?draft=${encodeURIComponent(draft.key)}`}>
              {draft.title || t('Untitled working copy')}
            </Link>
          ))}
        </section>
      )}
      <section className="admin-card">
        <div className="content-toolbar">
          <nav
            className="status-tabs"
            aria-label={t('Filter {items} by status', { items: collection })}
          >
            {[
              ['', t('All {collection}', { collection }), total],
              ['published', t('Published'), published],
              ['draft', t('Drafts'), drafts],
              ['scheduled', t('Scheduled'), scheduled],
              ['trash', t('Trash'), trash],
            ].map(([value, label, count]) => (
              <Link
                key={value}
                className={status === value ? 'selected' : ''}
                href={`${base}${value ? `?status=${value}` : ''}`}
              >
                {label} <span>{count}</span>
              </Link>
            ))}
          </nav>
          <form
            className="admin-search"
            action={base}
            method="get"
            onSubmit={(e) => {
              e.preventDefault();
              router.get(base, { q: search, status }, { preserveState: true });
            }}
          >
            <Icon name="search" />
            <label className="sr-only" htmlFor="content-search">
              {t('Search your {items}', { items: collection })}
            </label>
            <input
              id="content-search"
              type="search"
              name="q"
              maxLength={120}
              placeholder={t('Find content…')}
              value={search}
              onChange={(e) => setSearch(e.target.value)}
            />
            <input type="hidden" name="status" value={status} />
          </form>
        </div>
        {items.length ? (
          <ContentTable items={items} contentType={contentType} />
        ) : (
          <div className="empty-state">
            <Icon name="file" />
            <h2>{t('No content')}</h2>
            <p>
              {t('No {items} match this view. Clear your search or begin something new.', {
                items: collection,
              })}
            </p>
            <Link className="button button-outline" href={base}>
              {t('See all {items}', { items: collection })}
            </Link>
          </div>
        )}
      </section>
      <Pagination links={pagination} count={items.length} noun={collection} />
    </>
  );
}
Content.layout = (page: ReactNode) => <AdminLayout>{page}</AdminLayout>;
