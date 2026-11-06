import { SiteLink as Link, useSiteHref } from '../themes/navigation';
import { Head, usePage } from '@inertiajs/react';
import type { CSSProperties, ReactNode } from 'react';
import { useTranslation } from '../i18n';
import { defaultSite, type SharedProps } from '../types';
import PublicExtensions, { ExtensionSlot } from '../components/PublicExtensions';
import SiteNavigation from '../components/SiteNavigation';
import LanguageSwitcher from '../components/LanguageSwitcher';

const defaultLinks = [
  { id: 1, label: 'Home', url: '/', new_tab: 0 },
  { id: 2, label: 'Content', url: '/content', new_tab: 0 },
  { id: 3, label: 'About', url: '/about', new_tab: 0 },
];

export default function SiteLayout({ children }: { children: ReactNode }) {
  const { t } = useTranslation();
  const siteHref = useSiteHref();
  const { url, props } = usePage<SharedProps>();
  const { site = defaultSite, theme, navigation, pluginNavigation } = props;
  const style: Record<string, string> = {};
  for (const [field, variable] of [
    ['accent', '--green'],
    ['paper', '--paper'],
    ['ink', '--ink'],
    ['button_color', '--theme-button-background'],
    ['button_text_color', '--theme-button-text'],
  ]) {
    const value = theme?.settings[field];
    if (value && /^#[0-9a-f]{6}$/i.test(value)) style[variable] = value;
  }
  const width = Number(theme?.settings.width || 760);
  style['--content-width'] =
    `${Math.max(640, Math.min(960, Number.isFinite(width) ? width : 760))}px`;
  const stylesheet = theme?.layout === 'simple' ? theme.stylesheet : '';
  const path = url.split('?')[0];
  return (
    <div
      className="cms-site simple-site"
      data-cms-site
      data-layout="simple"
      style={style as CSSProperties}
    >
      {stylesheet && (
        <Head>
          <link head-key="cms-theme" rel="stylesheet" href={stylesheet} />
        </Head>
      )}
      <PublicExtensions />

      <div className="simple-shell">
        <ExtensionSlot name="site.top" />
        <a className="skip-link" href="#main">
          {t('Skip to content')}
        </a>
        <header className="simple-header">
          <Link className="simple-wordmark" href="/" aria-label={site.site_name}>
            {site.site_logo ? (
              <img className="site-brand-logo" src={site.site_logo} alt={site.site_name} />
            ) : (
              site.site_name
            )}
          </Link>
          <nav aria-label={t('Main navigation')}>
            <SiteNavigation links={navigation?.header || defaultLinks} path={path} />
            {pluginNavigation?.header.map((link) => (
              <a key={link.id} href={siteHref(link.href)}>
                {link.label}
              </a>
            ))}
          </nav>
          {site.description && <p>{site.description}</p>}
        </header>
        <main id="main" className="simple-main">
          {children}
        </main>
        <ExtensionSlot name="site.before-footer" />
        <footer className="simple-footer">
          <nav aria-label={t('Footer navigation')}>
            <SiteNavigation links={navigation?.footer || defaultLinks} path={path} />
            {pluginNavigation?.footer.map((link) => (
              <a key={link.id} href={siteHref(link.href)}>
                {link.label}
              </a>
            ))}
            <Link href="/admin/login">{t('Admin')}</Link>
          </nav>
          <div className="simple-footer-meta">
            <span>
              © {new Date().getUTCFullYear()} {site.site_name}
            </span>
            <LanguageSwitcher />
          </div>
        </footer>
        <ExtensionSlot name="site.footer" />
      </div>
    </div>
  );
}
