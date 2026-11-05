import type * as React from 'react';
import type { Head, Link, router, usePage } from '@inertiajs/react';
import type { ContentItem, SiteSettings } from '../types';
import type { useTranslation } from '../i18n';
import type { useSiteHref } from './navigation';
import type PageHead from '../components/PageHead';
import type Icon from '../components/Icon';
import type Markdown from '../components/Markdown';
import type Pagination from '../components/Pagination';
import type CategoryInput from '../components/CategoryInput';
import type SiteNavigation from '../components/SiteNavigation';
import type LanguageSwitcher from '../components/LanguageSwitcher';
import type PublicExtensions from '../components/PublicExtensions';
import type { ExtensionSlot } from '../components/PublicExtensions';
import type FieldValues from '../components/FieldValues';
import type ContentFilters from '../components/ContentFilters';

export const publicPages = [
  'Home',
  'ContentIndex',
  'ContentDetail',
  'Page',
  'About',
  'NotFound',
] as const;
export type PublicPageName = (typeof publicPages)[number];
export type ThemeLayout = React.ComponentType<{ children: React.ReactNode }>;
export type ThemeContentCard = React.ComponentType<{ item: ContentItem }>;
export type ThemePage = React.ComponentType<any> & {
  layout?: (page: React.ReactNode) => React.ReactNode;
};
export interface ThemeDefinition {
  pages: Partial<Record<string, ThemePage>>;
}
export interface ThemeRuntime {
  React: typeof React;
  Head: typeof Head;
  Link: typeof Link;
  router: typeof router;
  usePage: typeof usePage;
  useTranslation: typeof useTranslation;
  useSiteHref: typeof useSiteHref;
  PageHead: typeof PageHead;
  Icon: typeof Icon;
  Markdown: typeof Markdown;
  Pagination: typeof Pagination;
  CategoryInput: typeof CategoryInput;
  SiteNavigation: typeof SiteNavigation;
  LanguageSwitcher: typeof LanguageSwitcher;
  PublicExtensions: typeof PublicExtensions;
  ExtensionSlot: typeof ExtensionSlot;
  FieldValues: typeof FieldValues;
  ContentFilters: typeof ContentFilters;
  defaultSite: SiteSettings;
  asset: (path: string) => string;
}
export interface ThemeModule {
  createTheme: (runtime: ThemeRuntime) => ThemeDefinition;
}
