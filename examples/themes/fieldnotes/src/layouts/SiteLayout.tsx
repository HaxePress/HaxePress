import type { CSSProperties, ReactNode } from 'react';
import type { SharedProps } from '../../../../../resources/js/types';
import type {
  ThemeRuntime,
  ThemeLayout,
  ThemeContentCard,
} from '../../../../../resources/js/themes/types';

export function createSiteLayout(runtime: ThemeRuntime) {
  const {
    React,
    Head,
    Link,
    router,
    usePage,
    useTranslation,
    useSiteHref,
    Icon,
    PublicExtensions,
    ExtensionSlot,
    SiteNavigation,
    LanguageSwitcher,
    defaultSite,
  } = runtime;
  const { useEffect, useRef, useState } = React;
  function SiteLayout({ children }: { children: ReactNode }) {
    const { t } = useTranslation();
    const siteHref = useSiteHref();
    const {
      site = defaultSite,
      theme,
      navigation,
      pluginNavigation,
    } = usePage<SharedProps>().props;
    const themeStyle: Record<string, string> = {};
    for (const [field, variable] of [
      ['accent', '--green'],
      ['paper', '--paper'],
      ['ink', '--ink'],
      ['button_color', '--theme-button-background'],
      ['button_text_color', '--theme-button-text'],
    ]) {
      const value = theme?.settings[field];
      if (value && /^#[0-9a-f]{6}$/i.test(value)) themeStyle[variable] = value;
    }
    const width = Number(theme?.settings.width || 1180);
    themeStyle['--content-width'] =
      `${Number.isFinite(width) ? Math.max(960, Math.min(1440, width)) : 1180}px`;
    if (theme?.settings.typeface === 'modern')
      themeStyle['--serif'] = "'DM Sans', Arial, sans-serif";
    const { url } = usePage();
    const path = url.split('?')[0];
    const [menu, setMenu] = useState(false),
      [search, setSearch] = useState(false),
      [query, setQuery] = useState('');
    const dialog = useRef<HTMLDialogElement>(null);
    useEffect(() => {
      setMenu(false);
      setSearch(false);
    }, [url]);
    useEffect(() => {
      const el = dialog.current;
      if (!el) return;
      if (search && !el.open) el.showModal();
      else if (!search && el.open) el.close();
    }, [search]);
    useEffect(() => {
      const handler = (event: KeyboardEvent) => {
        if ((event.metaKey || event.ctrlKey) && event.key === 'k') {
          event.preventDefault();
          setSearch(true);
        }
      };
      document.addEventListener('keydown', handler);
      return () => document.removeEventListener('keydown', handler);
    }, []);
    const defaultLinks = [
      { id: 1, label: 'Home', url: '/', new_tab: 0 },
      { id: 2, label: 'Content', url: '/content', new_tab: 0 },
      { id: 3, label: 'About', url: '/about', new_tab: 0 },
    ];
    const nav = <SiteNavigation links={navigation?.header || defaultLinks} path={path} />;
    return (
      <div
        className="cms-site"
        data-cms-site
        data-layout={theme?.layout || 'fieldnotes'}
        style={themeStyle as CSSProperties}
      >
        {theme?.stylesheet && (
          <Head>
            <link head-key="cms-theme" rel="stylesheet" href={theme.stylesheet} />
          </Head>
        )}

        <PublicExtensions />
        <ExtensionSlot name="site.top" />
        <a className="skip-link" href="#main">
          {t('Skip to content')}
        </a>
        <header className="site-header wrap">
          <Link className="brand" href="/" aria-label={`${site.site_name} home`}>
            {site.site_logo ? (
              <img className="site-brand-logo" src={site.site_logo} alt={site.site_name} />
            ) : (
              <>
                <span className="brand-mark" aria-hidden="true">
                  ✳
                </span>
                <span>
                  {site.site_name}
                  <span className="brand-dot">.</span>
                </span>
              </>
            )}
          </Link>
          <nav className="desktop-nav" aria-label={t('Main navigation')}>
            {nav}
          </nav>
          <div className="header-actions">
            <button
              className="icon-button search-toggle"
              aria-label={t('Search content')}
              onClick={() => setSearch(true)}
            >
              <Icon name="search" />
            </button>
            {pluginNavigation?.header.map((link) => (
              <a className="button button-small" key={link.id} href={siteHref(link.href)}>
                {link.label}
                <Icon name={link.icon} />
              </a>
            ))}
            <button
              className="icon-button menu-toggle"
              aria-label={menu ? t('Close navigation') : t('Open navigation')}
              aria-expanded={menu}
              onClick={() => setMenu(!menu)}
            >
              <Icon name="menu" />
            </button>
          </div>
        </header>
        <nav className="mobile-nav wrap" aria-label={t('Mobile navigation')} hidden={!menu}>
          {nav}
        </nav>
        <main id="main">{children}</main>
        <ExtensionSlot name="site.before-footer" />
        <footer className="site-footer wrap">
          <div>
            <Link className="brand footer-brand" href="/">
              {site.site_logo ? (
                <img className="site-brand-logo" src={site.site_logo} alt={site.site_name} />
              ) : (
                <>
                  <span className="brand-mark" aria-hidden="true">
                    ✳
                  </span>
                  {site.site_name}
                  <span className="brand-dot">.</span>
                </>
              )}
            </Link>
            {site.description && <p>{site.description}</p>}
          </div>
          <div className="footer-right">
            <LanguageSwitcher />
            <nav aria-label={t('Footer navigation')}>
              <SiteNavigation links={navigation?.footer || defaultLinks} path={path} />
              {pluginNavigation?.footer.map((link) => (
                <a key={link.id} href={siteHref(link.href)}>
                  {link.label}
                  <Icon name={link.icon} />
                </a>
              ))}
              <Link href="/admin/login">
                {t('Admin')} <Icon name="arrow-up-right" />
              </Link>
            </nav>
            <p>
              © {new Date().getUTCFullYear()} {site.site_name}
            </p>
          </div>
        </footer>
        <ExtensionSlot name="site.footer" />
        <dialog
          ref={dialog}
          className="search-dialog"
          aria-labelledby="search-title"
          onCancel={(e) => {
            e.preventDefault();
            setSearch(false);
          }}
          onClick={(e) => {
            if (e.target === e.currentTarget) setSearch(false);
          }}
        >
          <form
            method="get"
            action={siteHref('/content')}
            onSubmit={(e) => {
              e.preventDefault();
              setSearch(false);
              router.get(siteHref('/content'), { q: query });
            }}
          >
            <div className="search-dialog-heading">
              <h2 id="search-title">{t('Search')}</h2>
              <button
                type="button"
                className="icon-button"
                onClick={() => setSearch(false)}
                aria-label={t('Close search')}
              >
                <Icon name="x" />
              </button>
            </div>
            <label htmlFor="global-search">{t('Search content')}</label>
            <div className="search-input">
              <Icon name="search" />
              <input
                id="global-search"
                name="q"
                type="search"
                placeholder={t('Search content')}
                value={query}
                onChange={(e) => setQuery(e.target.value)}
              />
              <button className="button" type="submit">
                {t('Search')}
              </button>
            </div>
            <p>{t('Try “home”, “morning”, or “travel”.')}</p>
          </form>
        </dialog>
      </div>
    );
  }
  return SiteLayout;
}
