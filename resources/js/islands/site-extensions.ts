// Activates the frontend modules of active plugins (docs/PLUGIN-PACKAGES.md, Hooks).
// Each module exports `activate(context)` and returns a cleanup function, or
// exports `deactivate(context)`.

type Message = string | { one: string; other: string };
type Parameters = Record<string, string | number>;

interface ExtensionModule {
  id: string;
  module: string;
  settings: Record<string, string>;
  messages: Record<string, Message>;
}

interface ExtensionContext {
  root: HTMLElement;
  settings: Record<string, string>;
  path: string;
  locale: string;
  t: (key: string, parameters?: Parameters) => string;
  slot: (name: string) => HTMLElement | null;
}

interface BrowserExtension {
  activate: (context: ExtensionContext) => void | (() => void) | Promise<void | (() => void)>;
  deactivate?: (context: ExtensionContext) => void;
}

/** Translates with the plugin's own catalogue; a missing key shows as written. */
function translator(messages: Record<string, Message>) {
  return (key: string, parameters: Parameters = {}) => {
    const message = Object.hasOwn(messages, key) ? messages[key] : key;
    const text =
      typeof message === 'string' ? message : parameters.count === 1 ? message.one : message.other;
    return text.replace(/\{([a-zA-Z][a-zA-Z0-9_]*)\}/g, (placeholder, name: string) =>
      Object.hasOwn(parameters, name) ? String(parameters[name]) : placeholder,
    );
  };
}

export async function mount(
  _element: HTMLElement,
  props: { modules: ExtensionModule[]; locale: string },
) {
  const root = document.querySelector<HTMLElement>('[data-cms-site]') || document.body;
  const path = `${window.location.pathname}${window.location.search}`;
  const slot = (name: string) =>
    Array.from(root.querySelectorAll<HTMLElement>('[data-extension-slot]')).find(
      (element) => element.dataset.extensionSlot === name,
    ) || null;
  // Modules download together and activate in the order of the plugins.
  const loading = props.modules.map(
    (entry) => import(/* @vite-ignore */ entry.module) as Promise<BrowserExtension>,
  );
  // A module that fails is reported when its turn comes.
  for (const pending of loading) pending.catch(() => {});
  const cleanups: (() => void)[] = [];
  for (const [index, entry] of props.modules.entries()) {
    try {
      const browserExtension = await loading[index];
      if (typeof browserExtension.activate !== 'function') {
        throw new Error('The module does not export activate.');
      }
      const context: ExtensionContext = {
        root,
        settings: entry.settings,
        path,
        locale: props.locale,
        t: translator(entry.messages || {}),
        slot,
      };
      const dispose = await browserExtension.activate(context);
      cleanups.push(
        typeof dispose === 'function' ? dispose : () => browserExtension.deactivate?.(context),
      );
    } catch (error) {
      console.error(`Extension could not be mounted: ${entry.id}`, error);
    }
  }
  return () => {
    for (const cleanup of cleanups.reverse()) cleanup();
  };
}
