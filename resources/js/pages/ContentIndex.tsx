import { SiteLink as Link } from '../themes/navigation';
import type { ReactNode } from 'react';
import { useTranslation } from '../i18n';
import type { PageLinks, ContentItem, Tag } from '../types';
import type { PublicCollection } from '../content';
import SiteLayout from '../layouts/SiteLayout';
import PageHead from '../components/PageHead';
import ContentCard from '../components/ContentCard';
import ContentFilters from '../components/ContentFilters';
import Pagination from '../components/Pagination';

export default function ContentIndex({
  items,
  query,
  category,
  resultCount,
  pagination,
  collection,
  archiveUrl,
  categories = [],
  fieldFilters = {},
  tag = null,
}: {
  items: ContentItem[];
  query: string;
  category: string;
  resultCount: number;
  pagination: PageLinks;
  collection: PublicCollection;
  archiveUrl: string;
  categories?: string[];
  fieldFilters?: Record<string, string>;
  tag?: Tag | null;
}) {
  const { t } = useTranslation();
  const filtered = Boolean(query || category || Object.values(fieldFilters).some(Boolean));
  return (
    <>
      <PageHead
        title={tag?.name || t(collection.name)}
        description={tag?.description || collection.description}
      />
      <header className="simple-page-heading">
        <h1>{tag?.name || t(collection.name)}</h1>
        {(tag?.description || collection.description) && (
          <p>{tag?.description || collection.description}</p>
        )}
        {tag && (
          <Link href={collection.publicBase}>
            {t('Back to {collection}', { collection: t(collection.name) })}
          </Link>
        )}
      </header>
      <ContentFilters
        collection={collection}
        path={archiveUrl}
        query={query}
        category={category}
        categories={categories}
        fieldFilters={fieldFilters}
        tag={tag?.slug}
      />
      <div className="simple-results">
        <p>{t('Result count', { count: resultCount })}</p>
        {filtered && (
          <Link href={archiveUrl + (tag ? '?tag=' + tag.slug + '&type=' + collection.key : '')}>
            {t('Clear search')}
          </Link>
        )}
      </div>
      {items.length > 0 ? (
        <div className="content-list">
          {items.map((item) => (
            <ContentCard key={item.id} item={item} />
          ))}
        </div>
      ) : (
        <div className="simple-empty">
          <h2>{t('No content here just yet.')}</h2>
          <p>{t('Try another word or change your filters.')}</p>
        </div>
      )}
      <Pagination links={pagination} count={items.length} />
    </>
  );
}
ContentIndex.layout = (page: ReactNode) => <SiteLayout>{page}</SiteLayout>;
