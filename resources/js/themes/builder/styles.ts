import type { Breakpoint, DesignBlock, ResponsiveStyles, StyleMap, ThemeDocument } from './types';
import {
  sectionsFor,
  visitBlocks,
  selectionFor,
  type DesignScope,
  type DesignSelection,
  type Interaction,
} from './types';

// Mirrors src/hx/press/view/DesignStyles.hx: every desktop rule, then one tablet and one mobile
// media block, classes before sections and blocks, with names and properties sorted.
const breakpoints: Breakpoint[] = ['desktop', 'tablet', 'mobile'];
const interactions = ['normal', 'hover', 'focus'] as const;

function declarations(properties: StyleMap): string {
  return Object.keys(properties)
    .sort()
    .map((property) => `${property}:${properties[property]};`)
    .join('');
}
function rules(layers: string[], selector: string, styles: ResponsiveStyles = {}): void {
  breakpoints.forEach((breakpoint, index) => {
    for (const interaction of interactions) {
      const values = styles[breakpoint]?.[interaction];
      if (!values || Object.keys(values).length === 0) continue;
      const suffix =
        interaction === 'normal' ? '' : interaction === 'focus' ? ':focus-visible' : ':hover';
      layers[index] += `${selector}${suffix}{${declarations(values)}}`;
    }
  });
}
function stylesheetScopes(document: ThemeDocument): DesignScope[] {
  const templates = Object.keys(document.templates).sort();
  const components = Object.keys(document.components || {})
    .sort()
    .map((id) => `@${id}`);
  return ['header', 'footer', ...templates, ...components];
}
export function designStyles(
  document: ThemeDocument,
  selection?: DesignSelection | null,
  preview?: { breakpoint: Breakpoint; interaction: Interaction; styleClass: string },
): string {
  const layers = ['', '', ''];
  const classes = document.classes || {};
  for (const name of Object.keys(classes).sort())
    rules(layers, `.hp-design .design-class-${name}`, classes[name]);
  for (const scope of stylesheetScopes(document)) {
    for (const section of sectionsFor(document, scope)) {
      const selector = `.hp-design [data-design-node="${section.id}"]`;
      const base: StyleMap = {
        'padding-block': `${section.padding}px`,
        'text-align': section.align,
      };
      if (section.background) base.background = section.background;
      if (section.color) base.color = section.color;
      layers[0] += `.hp-design :where([data-design-node="${section.id}"]){${baseDeclarations(base)}}`;
      rules(layers, selector, section.styles);
      visitBlocks(section.blocks, (node: DesignBlock) => {
        rules(layers, `.hp-design [data-design-node="${node.id}"]`, node.styles);
      });
    }
  }
  const [desktop, tablet, mobile] = layers;
  let css = desktop;
  if (tablet) css += `@media(max-width:900px){${tablet}}`;
  if (mobile) css += `@media(max-width:600px){${mobile}}`;
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
        ? `.design-class-${preview.styleClass}`
        : `[data-design-node="${selection?.block || selection?.section}"]`;
      css += `.hp-design.hp-design-editing ${target}{${declarations(values)}}`;
    }
  }
  return css;
}
// The section base keeps its fixed property order, as the server writes it.
function baseDeclarations(properties: StyleMap): string {
  return Object.entries(properties)
    .map(([property, value]) => `${property}:${value};`)
    .join('');
}
export function classNames(classes: string[] = []): string {
  return classes.flatMap((name) => [name, `design-class-${name}`]).join(' ');
}
