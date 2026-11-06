import { SiteLink as Link } from '../themes/navigation';
import type { NavigationLink } from '../types';
import { useTranslation } from '../i18n';
import { usePage } from '../page';
import type { SharedProps } from '../types';

export default function SiteNavigation({ links, path }: { links: NavigationLink[]; path: string }) {
  const { t } = useTranslation();
  const previewBase = usePage<SharedProps>().props.theme?.previewBase;
  const publicPath =
    previewBase && path.startsWith(previewBase) ? path.slice(previewBase.length) || '/' : path;
  return (
    <>
      {links.map((link) => {
        const active = link.url === publicPath;
        const options = {
          className: active ? 'active' : '',
          'aria-current': active ? ('page' as const) : undefined,
          target: link.new_tab === 1 ? '_blank' : undefined,
          rel: link.new_tab === 1 ? 'noopener noreferrer' : undefined,
        };
        return link.url.startsWith('/') && !link.new_tab ? (
          <Link key={link.id} href={link.url} {...options}>
            {t(link.label)}
          </Link>
        ) : (
          <a key={link.id} href={link.url} {...options}>
            {t(link.label)}
          </a>
        );
      })}
    </>
  );
}
