import { useTranslation } from '../i18n';
import { Link, router, usePage } from '@inertiajs/react';
import { useEffect, useRef, useState, type ReactNode } from 'react';
import Icon from '../components/Icon';
import Alert from '../components/Alert';
import LanguageSwitcher from '../components/LanguageSwitcher';
import { defaultSite, type SharedProps } from '../types';

interface NavigationLink {
  href: string;
  label: string;
  icon: string;
  exact: boolean;
  activePaths?: string[];
}
function isCurrent(link: NavigationLink, path: string) {
  const alias = link.activePaths?.some(
    (prefix) => path === prefix || path.startsWith(prefix + '/'),
  );
  return (
    Boolean(alias) ||
    (link.exact ? path === link.href : path === link.href || path.startsWith(link.href + '/'))
  );
}

function SidebarContent({ path, onNavigate }: { path: string; onNavigate?: () => void }) {
  const { t } = useTranslation();
  const {
    auth,
    csrfToken,
    site = defaultSite,
    adminNavigation = [],
  } = usePage<SharedProps>().props;
  const [busy, setBusy] = useState(false);
  const name = auth?.admin.name || 'Editor';
  const role = auth?.admin.roleLabel || 'Account';
  const initials = name
    .trim()
    .split(/\s+/)
    .slice(0, 2)
    .map((part) => part.charAt(0))
    .join('');

  return (
    <div className="sidebar-content">
      <Link className="admin-brand" href="/admin" onClick={onNavigate}>
        <span className="admin-brand-mark" aria-hidden="true">
          <Icon name="feather" />
        </span>
        <span>
          <strong>{site.site_name}</strong>
          <small>{t('Administration')}</small>
        </span>
      </Link>
      <div className="sidebar-navigation">
        <nav aria-label={t('Admin navigation')}>
          {adminNavigation.map((group) => {
            const links = group.links;
            if (!links.length) return null;
            return (
              <div className="admin-nav-group" key={group.label}>
                <span className="admin-nav-label">{group.label}</span>
                {links.map((link) => {
                  const { href, icon, label } = link;
                  const current = isCurrent(link, path);
                  return (
                    <Link
                      key={href}
                      className={current ? 'active' : ''}
                      aria-current={current ? 'page' : undefined}
                      href={href}
                      onClick={onNavigate}
                    >
                      <Icon name={icon} />
                      <span>{label}</span>
                    </Link>
                  );
                })}
              </div>
            );
          })}
        </nav>
      </div>
      <div className="sidebar-bottom">
        <Link href="/" className="visit-site" onClick={onNavigate}>
          <Icon name="external" />
          <span>{t('View website')}</span>
          <Icon name="arrow-up-right" />
        </Link>
        <div className="sidebar-profile">
          <Link
            className="admin-avatar"
            href="/admin/account"
            onClick={onNavigate}
            aria-label={t('Your account')}
          >
            {initials}
          </Link>
          <div>
            <strong>{name}</strong>
            <span className="role-label">{t(role)}</span>
          </div>
          <form
            action="/admin/logout"
            method="post"
            onSubmit={(event) => {
              event.preventDefault();
              onNavigate?.();
              router.post(
                '/admin/logout',
                { _token: csrfToken },
                {
                  onStart: () => setBusy(true),
                  onFinish: () => setBusy(false),
                },
              );
            }}
          >
            <input type="hidden" name="_token" value={csrfToken || ''} />
            <button className="icon-button" aria-label={t('Sign out')} disabled={busy}>
              <Icon name="logout" />
            </button>
          </form>
        </div>
      </div>
    </div>
  );
}

export default function AdminLayout({ children }: { children: ReactNode }) {
  const { t } = useTranslation();
  const { url, props } = usePage<SharedProps>();
  const { adminNavigation = [], pluginRestartRequired } = props;
  const path = url.split('?')[0];
  const currentLinks = adminNavigation
    .flatMap((group) => group.links.map((link) => ({ group, link })))
    .filter(({ link }) => isCurrent(link, path))
    .sort((left, right) => right.link.href.length - left.link.href.length);
  const current = currentLinks[0];
  const currentLabel = current?.link.label || t('Overview');
  const groupLabel = current?.group.label || t('Administration');
  const drawer = useRef<HTMLDialogElement>(null);
  const [navigationOpen, setNavigationOpen] = useState(false);

  function closeNavigation() {
    drawer.current?.close();
    setNavigationOpen(false);
  }

  useEffect(() => {
    const desktop = window.matchMedia('(min-width: 961px)');
    const closeOnDesktop = () => {
      if (desktop.matches) closeNavigation();
    };
    desktop.addEventListener('change', closeOnDesktop);
    return () => desktop.removeEventListener('change', closeOnDesktop);
  }, []);

  return (
    <div className="admin-body">
      <a className="skip-link" href="#main">
        {t('Skip to content')}
      </a>
      <aside className="admin-sidebar">
        <SidebarContent path={path} />
      </aside>
      <dialog
        ref={drawer}
        id="admin-mobile-navigation"
        className="admin-mobile-drawer"
        aria-label={t('Admin navigation')}
        onClose={() => setNavigationOpen(false)}
        onClick={(event) => {
          if (event.target === event.currentTarget) closeNavigation();
        }}
      >
        <button
          type="button"
          className="icon-button sidebar-close"
          onClick={closeNavigation}
          aria-label={t('Close navigation')}
        >
          <Icon name="x" />
        </button>
        <SidebarContent path={path} onNavigate={closeNavigation} />
      </dialog>
      <div className="admin-workspace">
        <header className="admin-topbar">
          <div className="admin-location">
            <button
              type="button"
              className="icon-button admin-menu-toggle"
              aria-label={t('Open navigation')}
              aria-controls="admin-mobile-navigation"
              aria-expanded={navigationOpen}
              onClick={() => {
                drawer.current?.showModal();
                setNavigationOpen(true);
              }}
            >
              <Icon name="menu" />
            </button>
            <nav className="admin-breadcrumbs" aria-label={t('Breadcrumb')}>
              <span>{groupLabel}</span>
              <Icon name="chevron-right" />
              <strong>{currentLabel}</strong>
            </nav>
          </div>
          <div className="admin-topbar-actions">
            <LanguageSwitcher />
            <Link href="/" className="button button-outline admin-website-link">
              {t('View website')} <Icon name="external" />
            </Link>
          </div>
        </header>
        <main id="main" className="admin-main">
          {pluginRestartRequired && (
            <Alert
              error
              message={t(
                'A plugin failed during creation or destruction. The server may not function as expected until it is restarted.',
              )}
            />
          )}
          {children}
        </main>
      </div>
    </div>
  );
}
