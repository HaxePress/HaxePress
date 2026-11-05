import type { ReactNode } from 'react';
import type { ContentItem, PageLinks, Tag } from '../../../../../resources/js/types';
import type { PublicCollection } from '../../../../../resources/js/content';
import type {
  ThemeRuntime,
  ThemeLayout,
  ThemeContentCard,
} from '../../../../../resources/js/themes/types';

export function createContentIndex(
  runtime: ThemeRuntime,
  SiteLayout: ThemeLayout,
  ContentCard: ThemeContentCard,
) {
  const { React, Link, useTranslation, PageHead, Pagination, ContentFilters } = runtime;
  function ContentIndex({
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
    return (
      <>
        <PageHead
          title={tag?.name || t(collection.name)}
          description={tag?.description || collection.description}
        />
        <section className="page-intro wrap">
          <p className="eyebrow">{t(collection.singular)}</p>
          <h1>{tag?.name || t(collection.name)}</h1>
          {(tag?.description || collection.description) && (
            <p>{tag?.description || collection.description}</p>
          )}
          {tag && (
            <Link href={collection.publicBase} className="text-link">
              {t('Back to {collection}', { collection: t(collection.name) })}
            </Link>
          )}
        </section>
        <section className="wrap">
          <ContentFilters
            collection={collection}
            path={archiveUrl}
            query={query}
            category={category}
            categories={categories}
            tag={tag?.slug}
            fieldFilters={fieldFilters}
          />
          <div className="results-meta">
            <p>{t('Result count', { count: resultCount })}</p>
            <Link href={archiveUrl + (tag ? '?tag=' + tag.slug + '&type=' + collection.key : '')}>
              {t('Clear search')}
            </Link>
          </div>
          {items.length ? (
            <div className="content-grid">
              {items.map((item) => (
                <ContentCard item={item} key={item.id} />
              ))}
            </div>
          ) : (
            <div className="empty-state">
              <h2>{t('No content here just yet.')}</h2>
              <p>{t('Try another word or change your filters.')}</p>
            </div>
          )}
          <Pagination links={pagination} count={items.length} />
        </section>
      </>
    );
  }
  ContentIndex.layout = (page: ReactNode) => <SiteLayout>{page}</SiteLayout>;
  return ContentIndex;
}
