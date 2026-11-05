import type { Breakpoint, DesignBlock, ResponsiveStyles, StyleMap, ThemeDocument } from './types';
import {
  scopesFor,
  sectionsFor,
  visitBlocks,
  selectionFor,
  type DesignSelection,
  type Interaction,
} from './types';

function declarations(properties: StyleMap): string {
  return Object.entries(properties)
    .map(([property, value]) => `${property}:${value};`)
    .join('');
}
function rules(selector: string, styles: ResponsiveStyles = {}): string {
  let css = '';
  for (const breakpoint of ['desktop', 'tablet', 'mobile'] as Breakpoint[]) {
    let device = '';
    for (const interaction of ['normal', 'hover', 'focus'] as const) {
      const values = styles[breakpoint]?.[interaction];
      if (!values || Object.keys(values).length === 0) continue;
      const suffix =
        interaction === 'normal' ? '' : interaction === 'focus' ? ':focus-visible' : ':hover';
      device += `${selector}${suffix}{${declarations(values)}}`;
    }
    if (breakpoint === 'desktop') css += device;
    else if (device) css += `@media(max-width:${breakpoint === 'tablet' ? 900 : 600}px){${device}}`;
  }
  return css;
}
export function designStyles(
  document: ThemeDocument,
  selection?: DesignSelection | null,
  preview?: { breakpoint: Breakpoint; interaction: Interaction; styleClass: string },
): string {
  let css = '';
  for (const [name, styles] of Object.entries(document.classes || {}))
    css += rules(`.hp-design .design-class-${name}`, styles);
  for (const scope of scopesFor(document)) {
    for (const section of sectionsFor(document, scope)) {
      const selector = `.hp-design [data-design-node="${section.id}"]`;
      const base: StyleMap = {
        'padding-block': section.padding + 'px',
        'text-align': section.align,
      };
      if (section.background) base.background = section.background;
      if (section.color) base.color = section.color;
      css += `.hp-design :where([data-design-node="${section.id}"]){${declarations(base)}}`;
      css += rules(selector, section.styles);
      visitBlocks(section.blocks, (node: DesignBlock) => {
        css += rules(`.hp-design [data-design-node="${node.id}"]`, node.styles);
      });
    }
  }
  if (document.css) css += `@scope (.hp-design){${document.css}}`;
  if (preview && preview.interaction !== 'normal') {
    const found = selectionFor(document, selection || null);
    const styles = preview.styleClass
      ? document.classes?.[preview.styleClass]
      : (found.block || found.section)?.styles;
    if (styles) {
      const values: StyleMap = { ...styles.desktop?.[preview.interaction] };
      if (preview.breakpoint !== 'desktop')
        Object.assign(values, styles.tablet?.[preview.interaction]);
      if (preview.breakpoint === 'mobile')
        Object.assign(values, styles.mobile?.[preview.interaction]);
      const target = preview.styleClass
        ? '.design-class-' + preview.styleClass
        : '[data-design-node="' + (selection?.block || selection?.section) + '"]';
      css += `.hp-design.hp-design-editing ${target}{${declarations(values)}}`;
    }
  }
  return css;
}
export function classNames(classes: string[] = []): string {
  return classes.flatMap((name) => [name, 'design-class-' + name]).join(' ');
}
