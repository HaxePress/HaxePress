import { usePage } from '@inertiajs/react';
import type { SharedProps } from './types';

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

export function useTranslation(namespace?: string) {
  const page = usePage<SharedProps>();
  const data = page.props.i18n;
  const selectedNamespace =
    namespace ?? (page.component.startsWith('Admin/') ? 'cms' : page.props.theme?.id || 'cms');
  return { ...data, t: createTranslator(data, selectedNamespace) };
}
