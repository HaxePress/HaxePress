import { Component, Suspense, type ReactNode } from 'react';
import { usePage } from '@inertiajs/react';
import { readTheme } from './themes/registry';
import type { ThemeDefinition, ThemePage } from './themes/types';
import type { SharedProps } from './types';
import { ThemeCustomizationBridge } from './themes/customization';
import DesignPage from './themes/builder/DesignPage';

const pages = import.meta.glob<{ default: ThemePage }>('./pages/**/*.tsx', { eager: true });
const wrappers = new Map<string, ThemePage>();

function renderedPage(page: ThemePage, props: Record<string, unknown>) {
  const Page = page;
  const element = <Page {...props} />;
  return Page.layout ? Page.layout(element) : element;
}

class ThemeBoundary extends Component<
  { children: ReactNode; fallback: ReactNode },
  { failed: boolean }
> {
  state = { failed: false };
  static getDerivedStateFromError() {
    return { failed: true };
  }
  componentDidCatch(error: Error) {
    console.error('Theme rendering failed.', error);
  }
  render() {
    return this.state.failed ? this.props.fallback : this.props.children;
  }
}

function LiveThemePage({
  name,
  fallback,
  pageProps,
}: {
  name: string;
  fallback: ThemePage;
  pageProps: Record<string, unknown>;
}) {
  const { theme } = usePage<SharedProps>().props;
  const definition = readTheme(theme);
  const selected =
    definition && Object.hasOwn(definition.pages, name)
      ? definition.pages[name] || fallback
      : fallback;
  return renderedPage(selected, pageProps);
}

function ThemeFrame({
  name,
  fallback,
  children,
  pageProps,
}: {
  name: string;
  fallback: ReactNode;
  children: ReactNode;
  pageProps: Record<string, unknown>;
}) {
  const { theme } = usePage<SharedProps>().props;
  return (
    <>
      <ThemeCustomizationBridge />
      <ThemeBoundary key={(theme?.renderer || 'simple') + name} fallback={fallback}>
        <Suspense fallback={<main className="theme-loading" aria-busy="true" />}>
          {theme?.design ? <DesignPage name={name} pageProps={pageProps} /> : children}
        </Suspense>
      </ThemeBoundary>
    </>
  );
}

function fallbackFor(name: string, props: Record<string, unknown>): ThemePage {
  const builtin = pages['./pages/' + name + '.tsx'];
  if (builtin) return builtin.default;
  const declared = typeof props.templateFallback === 'string' ? props.templateFallback : name;
  const safe = /^[A-Za-z][A-Za-z0-9_-]{0,79}$/.test(declared) ? declared : 'NotFound';
  return pages['./pages/' + safe + '.tsx']?.default || pages['./pages/NotFound.tsx'].default;
}

export function resolvePage(name: string, serverTheme?: ThemeDefinition | null): ThemePage {
  if (name.startsWith('Admin/')) {
    const page = pages['./pages/' + name + '.tsx'];
    if (!page) throw new Error('Unknown administration page: ' + name);
    return page.default;
  }
  if (!/^[A-Za-z][A-Za-z0-9_-]{0,79}$/.test(name)) {
    throw new Error('Invalid public template name.');
  }
  if (serverTheme !== undefined) {
    return function ServerThemePage(props) {
      const fallback = fallbackFor(name, props);
      const selected =
        serverTheme && Object.hasOwn(serverTheme.pages, name)
          ? serverTheme.pages[name] || fallback
          : fallback;
      return (
        <ThemeFrame name={name} fallback={renderedPage(fallback, props)} pageProps={props}>
          {renderedPage(selected, props)}
        </ThemeFrame>
      );
    };
  }
  const cached = wrappers.get(name);
  if (cached) return cached;
  function PublicThemePage(props: Record<string, unknown>) {
    const fallbackPage = fallbackFor(name, props);
    const fallback = renderedPage(fallbackPage, props);
    return (
      <ThemeFrame name={name} fallback={fallback} pageProps={props}>
        <LiveThemePage name={name} fallback={fallbackPage} pageProps={props} />
      </ThemeFrame>
    );
  }
  wrappers.set(name, PublicThemePage);
  return PublicThemePage;
}
