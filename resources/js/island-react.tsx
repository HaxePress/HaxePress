import { createRoot } from 'react-dom/client';
import type { ReactNode } from 'react';
import { TranslationProvider, loadCatalogue, type TranslationProps } from './i18n';

export interface IslandContext {
  /** The versioned URL of the CMS catalogue for the page's locale. */
  translations: string;
  locale: string;
  direction: string;
}

/** Mounts a React tree into a Wellout island with the CMS translations. */
export async function mountReact(element: HTMLElement, context: IslandContext, node: ReactNode) {
  const catalogue = await loadCatalogue(context.translations);
  const translations: TranslationProps = {
    locale: context.locale,
    direction: context.direction,
    fallbackLocale: 'en',
    locales: [],
    catalogues: { cms: catalogue },
  };
  const root = createRoot(element);
  root.render(<TranslationProvider value={translations}>{node}</TranslationProvider>);
  return () => root.unmount();
}
