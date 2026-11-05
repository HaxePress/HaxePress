import { SiteLink as Link } from '../themes/navigation';
import type { ReactNode } from 'react';
import { useTranslation } from '../i18n';
import type { ContentItem } from '../types';
import type { PublicCollection } from '../content';
import SiteLayout from '../layouts/SiteLayout';
import PageHead from '../components/PageHead';
import ContentCard from '../components/ContentCard';

export default function Home({
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
  const visibleItems = featured ? [featured, ...items] : items;
  return (
    <>
      <PageHead title={t('The latest content')} />
      <h1>{t('The latest content')}</h1>
      <div className="content-list">
        {visibleItems.map((item) => (
          <ContentCard key={item.id} item={item} />
        ))}
      </div>
      {visibleItems.length === 0 && (
        <p className="simple-empty">{t('No content here just yet.')}</p>
      )}
      {collection?.hasArchive && (
        <Link className="simple-archive-link" href={collection.publicBase}>
          {t('All content')} <span>({count})</span>
        </Link>
      )}
    </>
  );
}
Home.layout = (page: ReactNode) => <SiteLayout>{page}</SiteLayout>;
