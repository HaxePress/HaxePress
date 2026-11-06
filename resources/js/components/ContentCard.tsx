import { SiteLink as Link } from '../themes/navigation';
import type { ContentItem } from '../types';
import FieldValues from './FieldValues';

export default function ContentCard({ item }: { item: ContentItem }) {
  return (
    <article className="content-summary">
      <h2>
        <Link href={item.url}>{item.title}</Link>
      </h2>
      {item.excerpt && <p>{item.excerpt}</p>}
      <FieldValues definitions={item.fieldDefinitions} values={item.fields} />
      <div className="content-summary-meta">
        <time dateTime={item.published_at}>{item.publishedLabel}</time>
        {item.category && (
          <Link href={`${item.archiveUrl}?category=${encodeURIComponent(item.category)}`}>
            {item.category}
          </Link>
        )}
      </div>
    </article>
  );
}
