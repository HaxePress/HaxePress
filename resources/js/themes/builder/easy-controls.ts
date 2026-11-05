import {
  labelFor,
  type Breakpoint,
  type DesignBlock,
  type DesignSection,
  type Interaction,
  type ResponsiveStyles,
  type StyleMap,
  type ThemeDocument,
} from './types';

const pageNames: Record<string, string> = {
  Home: 'Home',
  ContentIndex: 'All content',
  ContentDetail: 'Content item',
  Page: 'Page',
  About: 'About',
  NotFound: 'Page not found',
  header: 'Header',
  footer: 'Footer',
};

export function easyPageName(document: ThemeDocument, scope: string): string {
  return pageNames[scope] || labelFor(document, scope);
}

export function templateIdentifier(label: string, document: ThemeDocument): string {
  const words = label
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .split(/[^A-Za-z0-9]+/)
    .filter(Boolean);
  let base = words.map((word) => word.charAt(0).toUpperCase() + word.slice(1)).join('');
  if (!/^[A-Za-z]/.test(base) || base.startsWith('Admin')) base = 'PageLayout' + base;
  base = (base || 'PageLayout').slice(0, 70);
  let candidate = base;
  let suffix = 2;
  while (Object.hasOwn(document.templates, candidate)) candidate = base + suffix++;
  return candidate;
}

export function inheritedStyles(
  styles: ResponsiveStyles = {},
  breakpoint: Breakpoint,
  interaction: Interaction,
): StyleMap {
  const values = { ...styles.desktop?.[interaction] };
  if (breakpoint !== 'desktop') Object.assign(values, styles.tablet?.[interaction]);
  if (breakpoint === 'mobile') Object.assign(values, styles.mobile?.[interaction]);
  return values;
}

/** Match the authored class/node cascade; custom CSS is available in the detailed controls. */
export function effectiveStyles(
  document: ThemeDocument,
  target: DesignBlock | DesignSection,
  breakpoint: Breakpoint,
  interaction: Interaction,
): StyleMap {
  const values: StyleMap = {};
  const classes = Object.entries(document.classes || {}).filter(([name]) =>
    target.classes?.includes(name),
  );
  for (const [, styles] of classes)
    Object.assign(values, inheritedStyles(styles, breakpoint, 'normal'));
  Object.assign(values, inheritedStyles(target.styles, breakpoint, 'normal'));
  if (interaction !== 'normal') {
    for (const [, styles] of classes)
      Object.assign(values, inheritedStyles(styles, breakpoint, interaction));
    Object.assign(values, inheritedStyles(target.styles, breakpoint, interaction));
  }
  return values;
}

export function layoutStyles(layout: 'stack' | 'row' | 'grid', columns = 3): StyleMap {
  if (layout === 'grid')
    return { display: 'grid', 'grid-template-columns': `repeat(${columns}, minmax(0, 1fr))` };
  return {
    display: 'flex',
    'flex-direction': layout === 'row' ? 'row' : 'column',
    'flex-wrap': layout === 'row' ? 'wrap' : 'nowrap',
  };
}
