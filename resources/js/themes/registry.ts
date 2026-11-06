import * as React from 'react';
import { Head, router, usePage } from '@inertiajs/react';
import { SiteLink as Link, useSiteHref } from './navigation';
import { useTranslation } from '../i18n';
import { defaultSite, type ThemeInfo } from '../types';
import PageHead from '../components/PageHead';
import Icon from '../components/Icon';
import Markdown from '../components/Markdown';
import Pagination from '../components/Pagination';
import CategoryInput from '../components/CategoryInput';
import SiteNavigation from '../components/SiteNavigation';
import LanguageSwitcher from '../components/LanguageSwitcher';
import PublicExtensions, { ExtensionSlot } from '../components/PublicExtensions';
import FieldValues from '../components/FieldValues';
import ContentFilters from '../components/ContentFilters';
import type { ThemeDefinition, ThemeModule, ThemeRuntime } from './types';

interface ThemeState {
  definition: ThemeDefinition | null;
  promise: Promise<ThemeDefinition | null>;
  settled: boolean;
}
const loaded = new Map<string, ThemeState>();
type ModuleLoader = (url: string) => Promise<ThemeModule>;
const browserLoader: ModuleLoader = (url) => import(/* @vite-ignore */ url);

function runtime(theme: ThemeInfo): ThemeRuntime {
  return {
    React,
    Head,
    Link,
    router,
    usePage,
    useTranslation,
    useSiteHref,
    PageHead,
    Icon,
    Markdown,
    Pagination,
    CategoryInput,
    SiteNavigation,
    LanguageSwitcher,
    PublicExtensions,
    ExtensionSlot,
    FieldValues,
    ContentFilters,
    defaultSite,
    asset(path) {
      if (
        !/^[A-Za-z0-9_/-]+(?:\.[A-Za-z0-9_-]+)+$/.test(path) ||
        path.split('/').some((part) => part.startsWith('.'))
      ) {
        throw new Error('Invalid theme asset path.');
      }
      return `${theme.assetBase}${path}`;
    },
  };
}

function trimCache() {
  for (const [key, state] of loaded) {
    if (loaded.size <= 24) break;
    if (state.settled) loaded.delete(key);
  }
}

export function prepareTheme(theme?: ThemeInfo | null, loader: ModuleLoader = browserLoader) {
  if (!theme?.renderer) return Promise.resolve(null);
  const cached = loaded.get(theme.renderer);
  if (cached) {
    loaded.delete(theme.renderer);
    loaded.set(theme.renderer, cached);
    return cached.promise;
  }
  const state: ThemeState = { definition: null, settled: false, promise: Promise.resolve(null) };
  state.promise = loader(theme.renderer)
    .then((module) => {
      if (typeof module.createTheme !== 'function')
        throw new Error('The theme must export createTheme.');
      const definition = module.createTheme(runtime(theme));
      if (!definition?.pages || !Object.keys(definition.pages).length) {
        throw new Error('The theme must provide at least one public template.');
      }
      for (const [name, page] of Object.entries(definition.pages)) {
        if (!/^[A-Za-z][A-Za-z0-9_-]{0,79}$/.test(name) || typeof page !== 'function') {
          throw new Error('The theme contains an invalid public template.');
        }
      }
      for (const template of theme.templates || []) {
        if (!Object.hasOwn(definition.pages, template.name)) {
          throw new Error(`The theme does not provide its declared template: ${template.name}`);
        }
      }
      state.definition = definition;
      return definition;
    })
    .catch((error) => {
      console.error(`Theme could not be loaded: ${theme.id}`, error);
      return null;
    })
    .finally(() => {
      state.settled = true;
      trimCache();
    });
  loaded.set(theme.renderer, state);
  return state.promise;
}

export function readTheme(theme?: ThemeInfo | null): ThemeDefinition | null {
  if (!theme?.renderer) return null;
  const state = loaded.get(theme.renderer);
  if (!state) throw prepareTheme(theme);
  if (!state.settled) throw state.promise;
  return state.definition;
}
