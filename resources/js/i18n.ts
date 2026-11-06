import { createContext, createElement, useContext, type ReactNode } from 'react';

export type TranslationMessage = string | { one: string; other: string };
export type TranslationParameters = Record<string, string | number>;
export type Translate = (key: string, parameters?: TranslationParameters) => string;
export interface TranslationProps {
  locale: string;
  direction: string;
  fallbackLocale: string;
  locales: { code: string; name: string; direction: string }[];
  catalogues: Record<string, Record<string, TranslationMessage>>;
}

export function createTranslator(data: TranslationProps, namespace = 'cms'): Translate {
  return (key, parameters = {}) => {
    const own = data.catalogues[namespace];
    const shared = data.catalogues.cms;
    const message =
      own && Object.hasOwn(own, key)
        ? own[key]
        : shared && Object.hasOwn(shared, key)
          ? shared[key]
          : key;
    const text =
      typeof message === 'string' ? message : parameters.count === 1 ? message.one : message.other;
    return text.replace(/\{([a-zA-Z][a-zA-Z0-9_]*)\}/g, (placeholder, name: string) =>
      Object.hasOwn(parameters, name) ? String(parameters[name]) : placeholder,
    );
  };
}

/** Translations for a client island, provided when it mounts. */
const IslandTranslations = createContext<TranslationProps | null>(null);

export function TranslationProvider({
  value,
  children,
}: {
  value: TranslationProps;
  children: ReactNode;
}) {
  return createElement(IslandTranslations.Provider, { value }, children);
}

const catalogues = new Map<string, Promise<Record<string, TranslationMessage>>>();

/** Loads the CMS catalogue an island needs from its cached, versioned URL. */
export function loadCatalogue(url: string): Promise<Record<string, TranslationMessage>> {
  let pending = catalogues.get(url);
  if (!pending) {
    pending = fetch(url, { credentials: 'same-origin' }).then((response) =>
      response.ok ? response.json() : {},
    );
    catalogues.set(url, pending);
  }
  return pending;
}

/** Used outside a translation provider, where keys show as written. */
const untranslated: TranslationProps = {
  locale: 'en',
  direction: 'ltr',
  fallbackLocale: 'en',
  locales: [],
  catalogues: {},
};

export function useTranslation(namespace?: string) {
  const data = useContext(IslandTranslations) ?? untranslated;
  return { ...data, t: createTranslator(data, namespace ?? 'cms') };
}
