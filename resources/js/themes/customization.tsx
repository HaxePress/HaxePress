import { router, usePage } from '@inertiajs/react';
import { useEffect } from 'react';
import type { ExtensionField, SharedProps } from '../types';

export interface ThemeCustomization {
  fields: ExtensionField[];
  values: Record<string, string>;
  session: string;
}

export const customizationMessages = {
  ready: 'haxepress:theme-customization-ready',
  update: 'haxepress:theme-customization-update',
  request: 'haxepress:theme-customization-request',
} as const;

/** Update native Inertia page props; theme components continue reading theme.settings. */
export function ThemeCustomizationBridge() {
  const { url, props } = usePage<SharedProps>();
  const theme = props.theme;
  const session = theme?.customizeSession;
  useEffect(() => {
    if (!theme || !session || !theme.previewBase || window.parent === window) return;
    const ready = () =>
      window.parent.postMessage(
        { type: customizationMessages.ready, themeId: theme.id, session },
        location.origin,
      );
    const receive = (event: MessageEvent) => {
      if (event.origin !== location.origin || event.source !== window.parent) return;
      const message = event.data;
      if (message?.session !== session || message.themeId !== theme.id) return;
      if (message.type === customizationMessages.request) {
        ready();
        return;
      }
      if (
        message.type !== customizationMessages.update ||
        !message.values ||
        typeof message.values !== 'object'
      )
        return;
      const settings: Record<string, string> = { ...theme.settings };
      for (const key of Object.keys(settings)) {
        const value: unknown = message.values[key];
        if (typeof value === 'string' && value.length <= 2000) settings[key] = value;
      }
      router.replaceProp('theme.settings', settings);
    };
    window.addEventListener('message', receive);
    ready();
    return () => window.removeEventListener('message', receive);
  }, [url, theme?.id, session]);
  return null;
}
