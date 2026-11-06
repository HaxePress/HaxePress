import type { TranslationProps } from './i18n';
import type { ContentFieldDefinition, CustomFieldValues } from './content';
import type { MediaRules } from './media';
import type { ThemeDocument } from './themes/builder/types';

export interface SiteSettings {
  locale: string;
  site_name: string;
  site_logo: string;
  publisher_name: string;
  description: string;
  about_site: string;
  home_mode: string;
  home_type: string;
  home_page: string;
  home_size: string;
  home_template: string;
}
export interface ContentItem {
  id: number | string;
  title: string;
  slug: string;
  excerpt: string;
  content?: string;
  category: string;
  image: string;
  image_alt: string;
  status: 'draft' | 'published' | 'scheduled' | 'trash';
  featured: boolean;
  published_at: string;
  publishedLabel: string;
  updated_at: string;
  updatedLabel: string;
  readMinutes: number;
  tags?: Tag[];
  content_type: string;
  url: string;
  archiveUrl: string;
  typeLabel: string;
  adminBase?: string;
  showReadingTime?: boolean;
  fields?: CustomFieldValues;
  fieldDefinitions?: ContentFieldDefinition[];
  version?: number;
  author_id?: number;
  seo_title?: string;
  seo_description?: string;
  scheduled_epoch?: number;
}
export interface Tag {
  id: number;
  name: string;
  slug: string;
  description: string;
  url?: string;
  items?: number;
}
export interface MediaImage {
  in_use?: boolean;
  id: number;
  filename: string;
  title: string;
  alt: string;
  url: string;
  mime_type: string;
  width: number;
  height: number;
  size: number;
}
export interface Subscriber {
  id: number;
  email: string;
  joined: string;
}
export interface Category {
  id: number;
  name: string;
  items: number;
}
export interface SharedProps {
  i18n: TranslationProps;
  [key: string]: unknown;
  site: SiteSettings;
  categories: string[];
  csrfToken: string | null;
  auth: {
    admin: {
      id: number;
      name: string;
      email: string;
      role: string;
      roleLabel: string;
      capabilities: string[];
    };
  } | null;
  errors: Record<string, string>;
  siteUrl: string;
  primaryArchive?: string;
  extensions?: { assets: ExtensionAsset[]; blocks: ExtensionBlock[] };
  pluginNavigation?: Record<
    'header' | 'footer' | 'admin',
    { id: string; label: string; href: string; icon: string }[]
  >;
  pluginRestartRequired?: boolean;
  mediaRules?: MediaRules;
  adminNavigation?: {
    label: string;
    links: {
      href: string;
      label: string;
      icon: string;
      exact: boolean;
      activePaths?: string[];
      parent?: string;
    }[];
  }[];
  theme?: ThemeInfo | null;
  themeFeeds?: Record<string, ContentItem[]>;
  navigation?: Record<string, NavigationLink[]>;
}
export interface NavigationLink {
  id: number;
  label: string;
  url: string;
  new_tab: number;
}
export interface ThemeInfo {
  id: string;
  built_in: boolean;
  name: string;
  slug: string;
  layout: string;
  stylesheet: string;
  module: string;
  assetBase: string;
  settings: Record<string, string>;
  preview: boolean;
  previewBase?: string;
  customizeSession?: string;
  studioSession?: string;
  studioScope?: string;
  design?: ThemeDocument | null;
  templates?: { name: string; label: string; scope: 'detail' | 'archive' | 'home' }[];
  navigation?: string[];
}
export interface ExtensionAsset {
  id: string;
  module: string;
  stylesheet: string;
  settings: Record<string, string>;
}
export interface ExtensionBlock {
  id: string;
  slot: string;
  content: string;
}
export interface PackageInspection {
  key: string;
  installedVersion: string | null;
  serverTarget: 'jvm' | 'cpp' | 'php' | '';
  repository?: string;
  manifest: {
    name: string;
    version: string;
    author: string;
    description: string;
    serverJar: string;
    serverCppia: string;
    serverPhp: string;
    module: string;
    stylesheet: string;
    layout: string;
  };
}

export interface ExtensionSummary {
  designed?: boolean;
  id: string;
  kind: 'plugin' | 'theme';
  name: string;
  slug: string;
  version: string;
  description: string;
  author: string;
  enabled: number;
  last_error: string;
  setting_count: number;
  restart_required: number;
  built_in: boolean;
  updated_at: string;
}
export interface ExtensionField {
  key: string;
  label: string;
  kind: 'text' | 'textarea' | 'boolean' | 'number' | 'color' | 'select' | 'secret';
  help: string;
  required: boolean;
  defaultValue: string;
  minimum: number;
  maximum: number;
  options: { label: string; value: string }[];
}
export const defaultSite: SiteSettings = {
  locale: 'en',
  home_mode: 'collection',
  home_type: 'entry',
  home_page: '0',
  home_size: '7',
  home_template: 'Home',
  site_name: 'HaxePress',
  site_logo: '',
  publisher_name: '',
  description: '',
  about_site: '',
};
export function errorText(value: unknown): string {
  if (typeof value === 'string') return value;
  if (value && typeof value === 'object')
    return Object.values(value).map(errorText).find(Boolean) || '';
  return '';
}

export interface PageLinks {
  previous: string | null;
  next: string | null;
  total: number;
}

export function hasCapability(capabilities: string[], capability: string): boolean {
  return capabilities.includes('*') || capabilities.includes(capability);
}
