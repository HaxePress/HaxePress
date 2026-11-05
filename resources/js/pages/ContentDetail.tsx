import { SiteLink as Link } from '../themes/navigation';
import { usePage } from '@inertiajs/react';
import { useEffect, useState, type ReactNode } from 'react';
import { useTranslation } from '../i18n';
import { defaultSite, type ContentItem, type SharedProps } from '../types';
import SiteLayout from '../layouts/SiteLayout';
import PageHead from '../components/PageHead';
import ContentCard from '../components/ContentCard';
import Markdown from '../components/Markdown';
import FieldValues from '../components/FieldValues';
import { ExtensionSlot } from '../components/PublicExtensions';

export default function ContentDetail({
  item,
  related,
}: {
  item: ContentItem;
  related: ContentItem[];
}) {
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
      if (navigator.share) await navigator.share({ title: item.title, url: window.location.href });
      else {
        await navigator.clipboard.writeText(window.location.href);
        setMessage(t('Link copied to clipboard.'));
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
      <article className="simple-content">
        <header>
          <Link href={item.archiveUrl}>{t('Back to content')}</Link>
          <h1>{item.title}</h1>
          <p className="simple-deck">{item.excerpt}</p>
          <div className="simple-byline">
            <span>{site.publisher_name || site.site_name}</span>
            <time dateTime={item.published_at}>{item.publishedLabel}</time>
            <span>{t('{count} min read', { count: item.readMinutes })}</span>
          </div>
          {(item.tags || []).length > 0 && (
            <nav className="simple-tags" aria-label={t('Content tags')}>
              {item.tags?.map((tag) => (
                <Link key={tag.id} href={tag.url || '/tags/' + tag.slug}>
                  #{tag.name}
                </Link>
              ))}
            </nav>
          )}
        </header>
        {item.image && <img className="content-cover" src={item.image} alt={item.image_alt} />}
        <div className="content-prose">
          <ExtensionSlot name="content.before" />
          <Markdown content={item.content || ''} />
          <FieldValues definitions={item.fieldDefinitions} values={item.fields} />
          <ExtensionSlot name="content.after" />
        </div>
        <footer className="simple-content-footer">
          <Link href={item.archiveUrl + '?category=' + encodeURIComponent(item.category)}>
            {item.category}
          </Link>
          <button className="button button-outline" onClick={share}>
            {t('Share this content item')}
          </button>
          {message && (
            <p role="status" aria-live="polite">
              {message}
            </p>
          )}
        </footer>
      </article>
      {related.length > 0 && (
        <section className="simple-related">
          <h2>{t('More content')}</h2>
          <div className="content-list">
            {related.map((item) => (
              <ContentCard key={item.id} item={item} />
            ))}
          </div>
        </section>
      )}
    </>
  );
}
ContentDetail.layout = (page: ReactNode) => <SiteLayout>{page}</SiteLayout>;
