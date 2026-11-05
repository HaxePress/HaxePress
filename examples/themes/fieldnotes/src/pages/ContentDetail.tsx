import type { ReactNode } from 'react';
import type { ContentItem, SharedProps } from '../../../../../resources/js/types';
import type {
  ThemeRuntime,
  ThemeLayout,
  ThemeContentCard,
} from '../../../../../resources/js/themes/types';

export function createContentDetail(
  runtime: ThemeRuntime,
  SiteLayout: ThemeLayout,
  ContentCard: ThemeContentCard,
) {
  const {
    React,
    Link,
    usePage,
    useTranslation,
    PageHead,
    Markdown,
    FieldValues,
    Icon,
    ExtensionSlot,
    defaultSite,
  } = runtime;
  const { useEffect, useState } = React;
  function ContentDetail({ item, related }: { item: ContentItem; related: ContentItem[] }) {
    const { t } = useTranslation();
    const { site = defaultSite } = usePage<SharedProps>().props;
    const [message, setMessage] = useState('');
    useEffect(() => {
      if (!message) return;
      const timer = setTimeout(() => setMessage(''), 4000);
      return () => clearTimeout(timer);
    }, [message]);
    async function share() {
      try {
        if (navigator.share)
          await navigator.share({ title: item.title, url: window.location.href });
        else {
          await navigator.clipboard.writeText(window.location.href);
          setMessage('Link copied to clipboard.');
        }
      } catch (error) {
        if (!(error instanceof Error) || error.name !== 'AbortError')
          setMessage(t('Copy this link: {url}', { url: window.location.href }));
      }
    }
    return (
      <>
        <PageHead
          title={item.seo_title || item.title}
          exactTitle={Boolean(item.seo_title)}
          description={item.seo_description || item.excerpt}
        />
        <article className="content-page wrap">
          <Link className="back-link" href={item.archiveUrl}>
            <Icon name="arrow-left" /> {t('Back to content')}
          </Link>
          <header className="content-header">
            <Link
              className="category-pill"
              href={item.archiveUrl + '?category=' + encodeURIComponent(item.category)}
            >
              {item.category}
            </Link>
            <h1>{item.title}</h1>
            <p className="content-deck">{item.excerpt}</p>
            {(item.tags || []).length > 0 && (
              <nav className="content-tags" aria-label={t('Content tags')}>
                {item.tags?.map((tag) => (
                  <Link key={tag.id} href={tag.url || '/tags/' + tag.slug}>
                    #{tag.name}
                  </Link>
                ))}
              </nav>
            )}
            <div className="content-byline">
              <div className="author-meta">
                <span className="author-avatar" aria-hidden="true">
                  {(site.publisher_name || site.site_name).charAt(0).toLowerCase()}.
                </span>
                <div>
                  <strong>{site.publisher_name || site.site_name}</strong>
                  <span>{item.publishedLabel}</span>
                </div>
              </div>
              <span>
                <Icon name="clock" /> {item.readMinutes} {t('min read')}
              </span>
              <button
                className="icon-button share-button"
                onClick={share}
                aria-label={t('Share this content item')}
              >
                <Icon name="share" />
              </button>
            </div>
          </header>
          {item.image && <img className="content-cover" src={item.image} alt={item.image_alt} />}
          <div className="content-prose">
            <ExtensionSlot name="content.before" />
            <Markdown content={item.content || ''} />
            <FieldValues definitions={item.fieldDefinitions} values={item.fields} />
            <ExtensionSlot name="content.after" />
            <div className="content-end">
              <button className="button button-outline" onClick={share}>
                <Icon name="share" /> {t('Share this content item')}
              </button>
            </div>
          </div>
        </article>
        <section className="wrap related-content">
          <div className="section-heading">
            <div>
              <h2>{t('Related content')}</h2>
            </div>
            <Link className="text-link" href={item.archiveUrl}>
              {t('All content')} <Icon name="arrow-right" />
            </Link>
          </div>
          <div className="content-grid">
            {related.map((item) => (
              <ContentCard key={item.id} item={item} />
            ))}
          </div>
        </section>
        {message && (
          <div className="toast" role="status" aria-live="polite">
            {t(message)}
          </div>
        )}
      </>
    );
  }
  ContentDetail.layout = (page: ReactNode) => <SiteLayout>{page}</SiteLayout>;
  return ContentDetail;
}
