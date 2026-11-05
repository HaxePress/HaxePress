import { SiteLink as Link } from '../themes/navigation';
import { useTranslation } from '../i18n';
import Icon from './Icon';
import type { PageLinks } from '../types';

export default function Pagination({
  links,
  count,
  noun = 'content items',
}: {
  links: PageLinks;
  count: number;
  noun?: string;
}) {
  const { t } = useTranslation();
  if (!links.previous && !links.next) return null;
  return (
    <nav className="pagination" aria-label={t('Pagination')}>
      <span>
        {t('Showing {count} of {total} {items}', { count, total: links.total, items: t(noun) })}
      </span>
      <div>
        {links.previous ? (
          <Link className="button button-outline" href={links.previous} preserveState>
            <Icon name="arrow-left" /> {t('Previous')}
          </Link>
        ) : (
          <span />
        )}
        {links.next && (
          <Link className="button button-outline" href={links.next} preserveState>
            {t('Next')} <Icon name="arrow-right" />
          </Link>
        )}
      </div>
    </nav>
  );
}
