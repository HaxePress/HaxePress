import type { PublicCollection } from '../../../../../resources/js/content';
import type { ReactNode } from 'react';
import type { ContentItem, SharedProps } from '../../../../../resources/js/types';
import type {
  ThemeRuntime,
  ThemeLayout,
  ThemeContentCard,
} from '../../../../../resources/js/themes/types';

export function createHome(
  runtime: ThemeRuntime,
  SiteLayout: ThemeLayout,
  ContentCard: ThemeContentCard,
) {
  const { React, Link, usePage, useTranslation, PageHead, Icon, defaultSite } = runtime;
  function Home({
    featured,
    items,
    count,
    collection,
  }: {
    featured: ContentItem | null;
    items: ContentItem[];
    count: number;
    collection: PublicCollection | null;
  }) {
    const { t } = useTranslation();
    const { site = defaultSite, categories = [] } = usePage<SharedProps>().props;
    return (
      <>
        <PageHead title={t('Home')} />
        <div className="wrap theme-home">
          {featured && (
            <article className="featured-content">
              <Link className="featured-image" href={featured.url} aria-label={featured.title}>
                {featured.image ? (
                  <img src={featured.image} alt={featured.image_alt} fetchPriority="high" />
                ) : (
                  <span className="content-image-placeholder" aria-hidden="true">
                    ✳
                  </span>
                )}
                <span className="featured-badge">
                  <Icon name="sparkles" /> {t('In the spotlight')}
                </span>
              </Link>
              <div className="featured-copy">
                <div className="featured-topline">
                  <Link
                    className="category-pill living"
                    href={
                      featured.archiveUrl + '?category=' + encodeURIComponent(featured.category)
                    }
                  >
                    {featured.category}
                  </Link>
                  <span>
                    <Icon name="clock" /> {t('{count} min read', { count: featured.readMinutes })}
                  </span>
                </div>
                <h2>
                  <Link href={featured.url}>{featured.title}</Link>
                </h2>
                <p>{featured.excerpt}</p>
                <div className="featured-bottom">
                  <div className="author-meta">
                    <span className="author-avatar" aria-hidden="true">
                      {(site.publisher_name || site.site_name).charAt(0).toLowerCase()}.
                    </span>
                    <div>
                      <strong>{site.publisher_name || site.site_name}</strong>
                      <span>{featured.publishedLabel}</span>
                    </div>
                  </div>
                  <Link
                    className="round-link"
                    href={featured.url}
                    aria-label={t('Read {title}', { title: featured.title })}
                  >
                    <Icon name="arrow-up-right" />
                  </Link>
                </div>
              </div>
            </article>
          )}
          <section className="latest-section" id="latest">
            <div className="section-heading">
              <div>
                <h2>
                  {t('The latest content')}
                  <span className="heading-dot">.</span>
                </h2>
              </div>
              <Link
                className="text-link"
                href={collection?.hasArchive ? collection.publicBase : '/'}
              >
                {t('Explore content')} <Icon name="arrow-right" />
              </Link>
            </div>
            <nav className="category-bar" aria-label={t('Content item categories')}>
              <Link
                className="filter selected"
                href={collection?.hasArchive ? collection.publicBase : '/'}
              >
                {t('All content')} <span>{count}</span>
              </Link>
              {categories.map((category) => (
                <Link
                  className="filter"
                  key={category}
                  href={
                    (collection?.publicBase || '/') + '?category=' + encodeURIComponent(category)
                  }
                >
                  {category}
                </Link>
              ))}
              <Link
                className="category-search"
                href={collection?.hasArchive ? collection.publicBase : '/'}
                aria-label={t('Search content')}
              >
                <Icon name="search" />
              </Link>
            </nav>
            <div className="content-grid">
              {items.map((item) => (
                <ContentCard key={item.id} item={item} />
              ))}
            </div>
            <div className="more-content">
              <Link
                className="button button-outline"
                href={collection?.hasArchive ? collection.publicBase : '/'}
              >
                {t('All content')} <Icon name="arrow-down" />
              </Link>
            </div>
          </section>
          {site.about_site && (
            <section className="about-strip">
              <div>
                <h2>{t('About this site')}</h2>
                <p>{site.about_site}</p>
              </div>
              <Link className="round-link" href="/about" aria-label={t('About this site')}>
                <Icon name="arrow-up-right" />
              </Link>
            </section>
          )}
        </div>
      </>
    );
  }
  Home.layout = (page: ReactNode) => <SiteLayout>{page}</SiteLayout>;
  return Home;
}
