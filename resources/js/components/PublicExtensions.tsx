import { Head, usePage } from '@inertiajs/react';
import { useEffect } from 'react';
import Markdown from './Markdown';
import type { SharedProps } from '../types';
import { createTranslator, type Translate } from '../i18n';

interface ExtensionContext {
  root: HTMLElement;
  settings: Record<string, string>;
  path: string;
  locale: string;
  t: Translate;
  slot: (name: string) => HTMLElement | null;
}
interface BrowserExtension {
  activate: (context: ExtensionContext) => void | (() => void) | Promise<void | (() => void)>;
  deactivate?: (context: ExtensionContext) => void;
}

export function ExtensionSlot({ name }: { name: string }) {
  const { extensions, theme } = usePage<SharedProps>().props;
  const blocks = extensions?.blocks.filter((block) => block.slot === name) || [];
  return (
    <div
      className={`extension-slot extension-slot-${name.replace('.', '-')}`}
      data-extension-slot={name}
      inert={theme?.studioSession ? true : undefined}
    >
      {blocks.map((block) => (
        <div className="extension-block" key={block.id}>
          <Markdown content={block.content} />
        </div>
      ))}
    </div>
  );
}

export default function PublicExtensions() {
  const { extensions, theme, i18n } = usePage<SharedProps>().props;
  const { url } = usePage();
  const assets = [...(extensions?.assets || [])];
  if (theme?.module)
    assets.push({ id: theme.id, module: theme.module, stylesheet: '', settings: theme.settings });
  const signature = JSON.stringify({ assets, locale: i18n.locale });
  useEffect(() => {
    let cancelled = false;
    const cleanups: (() => void)[] = [];
    const root = document.querySelector<HTMLElement>('[data-cms-site]') || document.body;
    async function mount() {
      for (const asset of assets) {
        if (!asset.module || cancelled) continue;
        try {
          const extension: BrowserExtension = await import(/* @vite-ignore */ asset.module);
          if (cancelled) return;
          const context: ExtensionContext = {
            root,
            settings: asset.settings,
            path: url,
            locale: i18n.locale,
            t: createTranslator(i18n, asset.id),
            slot: (name) =>
              Array.from(root.querySelectorAll<HTMLElement>('[data-extension-slot]')).find(
                (slot) => slot.dataset.extensionSlot === name,
              ) || null,
          };
          const dispose = await extension.activate(context);
          const cleanup =
            typeof dispose === 'function' ? dispose : () => extension.deactivate?.(context);
          if (cancelled) cleanup();
          else cleanups.push(cleanup);
        } catch (error) {
          console.error(`Extension could not be mounted: ${asset.id}`, error);
        }
      }
    }
    void mount();
    return () => {
      cancelled = true;
      for (const cleanup of cleanups.reverse()) cleanup();
    };
  }, [signature, url]);
  return (
    <Head>
      {assets
        .filter((asset) => asset.stylesheet)
        .map((asset) => (
          <link
            key={asset.id}
            head-key={`extension-${asset.id}`}
            rel="stylesheet"
            href={asset.stylesheet}
          />
        ))}
    </Head>
  );
}
