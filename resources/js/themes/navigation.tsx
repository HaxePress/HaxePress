import { Link as PageLink, usePage } from '../page';
import { forwardRef, type ComponentProps } from 'react';
import type { SharedProps } from '../types';

export function previewHref(
  href: string,
  base?: string,
  locale?: string,
  customizeSession?: string,
): string {
  if (!base || !href.startsWith('/') || href.startsWith('//')) return href;
  const url = new URL(href, 'http://preview.local');
  const first = url.pathname.split('/')[1];
  const reserved = [
    'admin',
    'api',
    'media',
    'storage',
    'build',
    'fonts',
    'images',
    'themes',
    'packages',
    'extension-assets',
    'locale',
  ];
  const publicPage =
    url.pathname === '/' ||
    (/^\/[a-z0-9-]+(?:\/[a-z0-9-]+)?$/.test(url.pathname) && !reserved.includes(first));
  if (!publicPage) return href;
  if (locale) url.searchParams.set('lang', locale);
  if (customizeSession) url.searchParams.set('customizeSession', customizeSession);
  const pathname = url.pathname === '/' ? '' : url.pathname;
  return `${base}${pathname}${url.search}${url.hash}`;
}

export function useSiteHref() {
  const { theme, i18n } = usePage<SharedProps>().props;
  return (href: string) =>
    previewHref(href, theme?.previewBase, i18n.locale, theme?.customizeSession);
}

export const SiteLink = forwardRef<HTMLAnchorElement, ComponentProps<typeof PageLink>>(
  function SiteLink({ href, ...props }, ref) {
    const siteHref = useSiteHref();
    const destination = typeof href === 'string' ? siteHref(href) : href;
    return <PageLink {...props} href={destination} ref={ref} />;
  },
);
