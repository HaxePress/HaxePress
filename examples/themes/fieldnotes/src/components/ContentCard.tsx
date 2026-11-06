import type { ContentItem, SharedProps } from '../../../../../resources/js/types';
import type {
  ThemeRuntime,
  ThemeLayout,
  ThemeContentCard,
} from '../../../../../resources/js/themes/types';

export function createContentCard(runtime: ThemeRuntime) {
  const { React, Link, usePage, useTranslation, Icon, defaultSite, FieldValues } = runtime;
  function ContentCard({ item }: { item: ContentItem }) {
    const { t } = useTranslation();
    const { site = defaultSite } = usePage<SharedProps>().props;
    return (
      <article className="content-card">
        <Link className="content-image" href={item.url} aria-label={item.title}>
          {item.image ? (
            <img src={item.image} alt={item.image_alt} loading="lazy" />
          ) : (
            <span className="content-image-placeholder" aria-hidden="true">
              ✳
            </span>
          )}
          <span className="image-arrow">
            <Icon name="arrow-up-right" />
          </span>
        </Link>
        <div className="card-topline">
          <Link
            className={`category-pill ${item.category.toLowerCase().replaceAll(' ', '-')}`}
            href={`${item.archiveUrl}?category=${encodeURIComponent(item.category)}`}
          >
            {item.category}
          </Link>
          <span>{t('{count} min read', { count: item.readMinutes })}</span>
        </div>
        <h3>
          <Link href={item.url}>{item.title}</Link>
        </h3>
        <p>{item.excerpt}</p>
        <FieldValues definitions={item.fieldDefinitions} values={item.fields} />
        <div className="card-meta">
          <span>{item.publishedLabel}</span>
          <span className="meta-dot" />
          <span>{site.publisher_name || site.site_name}</span>
        </div>
      </article>
    );
  }
  return ContentCard;
}
