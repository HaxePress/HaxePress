export const templateNames = [
  'Home',
  'ContentIndex',
  'ContentDetail',
  'Page',
  'About',
  'NotFound',
] as const;
export type TemplateName = (typeof templateNames)[number];
export type DesignScope = string;
export const templateLabels: Record<string, string> = {
  Home: 'Homepage',
  ContentIndex: 'Content archive',
  ContentDetail: 'Content detail',
  Page: 'Page',
  About: 'About',
  NotFound: '404 page',
  header: 'Header',
  footer: 'Footer',
};
export const blockLabels = {
  container: 'Container',
  element: 'HTML element',
  heading: 'Heading',
  text: 'Text',
  image: 'Image',
  button: 'Button',
  spacer: 'Space',
  divider: 'Divider',
  brand: 'Site logo and name',
  navigation: 'Navigation',
  repeat: 'Content repeater',
  component: 'Reusable component',
  extension: 'Plugin slot',
  pagination: 'Pagination',
  search: 'Content filters',
  'content-list': 'Content list',
  'content-title': 'Content title',
  'content-excerpt': 'Content excerpt',
  'content-image': 'Content image',
  'content-body': 'Content body',
  'site-description': 'Site description',
} as const;
export type BlockType = keyof typeof blockLabels;
export type Breakpoint = 'desktop' | 'tablet' | 'mobile';
export type Interaction = 'normal' | 'hover' | 'focus';
export type StyleMap = Record<string, string>;
export type ResponsiveStyles = Partial<Record<Breakpoint, Partial<Record<Interaction, StyleMap>>>>;
export interface DesignBlock {
  id: string;
  type: BlockType;
  text: string;
  href: string;
  image: string;
  alt: string;
  level: number;
  name?: string;
  tag?: string;
  children?: DesignBlock[];
  styles?: ResponsiveStyles;
  classes?: string[];
  attributes?: Record<string, string>;
  bindings?: Record<string, string>;
  source?: string;
  component?: string;
  slot?: string;
  condition?: { field: string; operator: 'present' | 'empty' | 'equals'; value: string };
}
export interface DesignSection {
  id: string;
  name: string;
  background: string;
  color: string;
  padding: number;
  columns: number;
  align: 'left' | 'center' | 'right';
  width: 'content' | 'wide' | 'full';
  blocks: DesignBlock[];
  styles?: ResponsiveStyles;
  classes?: string[];
}
export interface DesignFeed {
  id: string;
  name: string;
  collection: string;
  limit: number;
  category: string;
  tag: string;
  query: string;
  order: 'published_at' | 'title' | 'id';
  direction: 'ASC' | 'DESC';
}
export interface ThemeDocument {
  schema: 1 | 2;
  tokens: {
    background: string;
    text: string;
    accent: string;
    font: string;
    width: number;
    radius: number;
  };
  header: DesignSection[];
  footer: DesignSection[];
  templates: Record<string, DesignSection[]>;
  templateMeta?: Record<string, { label: string; fallback: TemplateName }>;
  components?: Record<string, { name: string; sections: DesignSection[] }>;
  classes?: Record<string, ResponsiveStyles>;
  feeds?: DesignFeed[];
  css?: string;
}
export interface DesignSelection {
  scope: DesignScope;
  section: string;
  block?: string;
}
export interface DesignDrag extends DesignSelection {
  position?: 'before' | 'after' | 'inside';
}
export const designMessages = {
  ready: 'haxepress:design-ready',
  request: 'haxepress:design-request',
  update: 'haxepress:design-update',
  select: 'haxepress:design-select',
  move: 'haxepress:design-move',
  insert: 'haxepress:design-insert',
  resize: 'haxepress:design-resize',
  editText: 'haxepress:design-edit-text',
  chooseImage: 'haxepress:design-choose-image',
} as const;
export const MAX_NODES = 2048;
export const MAX_DEPTH = 16;
export const MAX_BYTES = 1048576;
export const MAX_MCP_REQUEST_BYTES = 8 * 1048576;
export const htmlTags = [
  'div',
  'section',
  'article',
  'aside',
  'header',
  'footer',
  'nav',
  'main',
  'figure',
  'figcaption',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'p',
  'span',
  'a',
  'strong',
  'em',
  'small',
  'blockquote',
  'ul',
  'ol',
  'li',
  'dl',
  'dt',
  'dd',
  'details',
  'summary',
  'time',
  'label',
  'form',
  'input',
  'textarea',
  'select',
  'option',
  'button',
  'table',
  'thead',
  'tbody',
  'tr',
  'th',
  'td',
  'br',
  'hr',
  'pre',
  'code',
  'svg',
  'path',
  'g',
  'defs',
  'circle',
  'ellipse',
  'rect',
  'line',
  'polyline',
  'polygon',
  'linearGradient',
  'radialGradient',
  'stop',
  'clipPath',
  'mask',
  'use',
  'title',
  'desc',
  'text',
] as const;
export const voidTags: readonly string[] = ['input', 'br', 'hr'];
export const containerTypes: readonly string[] = ['container', 'element', 'repeat'];

export function canContain(block: DesignBlock): boolean {
  if (block.type === 'container' || block.type === 'repeat') return true;
  return (
    block.type === 'element' &&
    ![
      'input',
      'br',
      'hr',
      'p',
      'span',
      'a',
      'strong',
      'em',
      'small',
      'h1',
      'h2',
      'h3',
      'h4',
      'h5',
      'h6',
      'button',
      'textarea',
      'select',
      'option',
      'time',
      'code',
      'path',
      'circle',
      'ellipse',
      'rect',
      'line',
      'polyline',
      'polygon',
      'stop',
      'text',
    ].includes(block.tag || 'div')
  );
}

export function upgradeDocument(input: ThemeDocument): ThemeDocument {
  const document = structuredClone(input);
  document.schema = 2;
  document.components ||= {};
  document.classes ||= {};
  document.feeds ||= [];
  document.templateMeta ||= {};
  document.css ||= '';
  return document;
}
export function scopesFor(document: ThemeDocument): string[] {
  return [
    'header',
    'footer',
    ...Object.keys(document.templates),
    ...Object.keys(document.components || {}).map((id) => '@' + id),
  ];
}
export function labelFor(document: ThemeDocument, scope: string): string {
  if (scope.startsWith('@')) return document.components?.[scope.slice(1)]?.name || 'Component';
  return document.templateMeta?.[scope]?.label || templateLabels[scope] || scope;
}
export function sectionsFor(document: ThemeDocument, scope: DesignScope): DesignSection[] {
  if (scope === 'header' || scope === 'footer') return document[scope];
  if (scope.startsWith('@')) return document.components?.[scope.slice(1)]?.sections || [];
  return document.templates[scope] || [];
}
export function findBlock(blocks: DesignBlock[], id?: string): DesignBlock | undefined {
  if (!id) return undefined;
  for (const block of blocks) {
    if (block.id === id) return block;
    const found = findBlock(block.children || [], id);
    if (found) return found;
  }
}
export function findBlockLocation(
  blocks: DesignBlock[],
  id: string,
): { list: DesignBlock[]; index: number; parent?: DesignBlock } | undefined {
  const index = blocks.findIndex((block) => block.id === id);
  if (index !== -1) return { list: blocks, index };
  for (const block of blocks) {
    const found = findBlockLocation(block.children || [], id);
    if (found) return { ...found, parent: found.parent || block };
  }
}
export function selectionFor(document: ThemeDocument, selection: DesignSelection | null) {
  const section = selection
    ? sectionsFor(document, selection.scope).find((section) => section.id === selection.section)
    : undefined;
  return { section, block: findBlock(section?.blocks || [], selection?.block) };
}
export function visitBlocks(blocks: DesignBlock[], callback: (block: DesignBlock) => void): void {
  for (const block of blocks) {
    callback(block);
    visitBlocks(block.children || [], callback);
  }
}
export function cloneBlock(block: DesignBlock): DesignBlock {
  return {
    ...structuredClone(block),
    id: crypto.randomUUID(),
    children: (block.children || []).map(cloneBlock),
  };
}
export function cloneSection(section: DesignSection): DesignSection {
  return {
    ...structuredClone(section),
    id: crypto.randomUUID(),
    blocks: section.blocks.map(cloneBlock),
  };
}
export function newBlock(type: BlockType): DesignBlock {
  const text =
    type === 'heading'
      ? 'Your heading'
      : type === 'text'
        ? 'Add your text here.'
        : type === 'button'
          ? 'Learn more'
          : '';
  return {
    id: crypto.randomUUID(),
    type,
    text,
    href: type === 'button' ? '/' : '',
    image: '',
    alt: '',
    level: 2,
    name: '',
    children: [],
    tag: 'div',
    styles: {},
    bindings: {},
    attributes: {},
    classes: [],
    source: 'page.items',
  };
}
export function newSection(name = 'Section'): DesignSection {
  return {
    id: crypto.randomUUID(),
    name,
    background: '',
    color: '',
    padding: 48,
    columns: 1,
    align: 'left',
    width: 'content',
    blocks: [],
    styles: {},
    classes: [],
  };
}
export function setStyle(
  styles: ResponsiveStyles,
  breakpoint: Breakpoint,
  interaction: Interaction,
  property: string,
  value: string,
): void {
  const device = (styles[breakpoint] ||= {});
  const state = (device[interaction] ||= {});
  if (value === '') delete state[property];
  else state[property] = value;
}

/** Move owned design nodes, including into containers, without introducing cycles. */
export function moveDesignEntry(
  document: ThemeDocument,
  source: DesignDrag,
  target: DesignDrag,
): boolean {
  if (!scopesFor(document).includes(source.scope) || !scopesFor(document).includes(target.scope))
    return false;
  const from = sectionsFor(document, source.scope);
  const to = sectionsFor(document, target.scope);
  const position = target.position || 'before';
  if (!source.block) {
    if (target.block || (source.scope === target.scope && source.section === target.section))
      return false;
    const index = from.findIndex((section) => section.id === source.section);
    if (index < 0) return false;
    const [section] = from.splice(index, 1);
    const destination = to.findIndex((entry) => entry.id === target.section);
    to.splice(
      destination < 0 ? to.length : destination + (position === 'after' ? 1 : 0),
      0,
      section,
    );
    return true;
  }
  const sourceSection = from.find((section) => section.id === source.section);
  const targetSection = to.find((section) => section.id === target.section);
  if (!sourceSection || !targetSection) return false;
  const sourceLocation = findBlockLocation(sourceSection.blocks, source.block);
  if (!sourceLocation) return false;
  const node = sourceLocation.list[sourceLocation.index];
  if (source.block === target.block || findBlock(node.children || [], target.block)) return false;
  const targetNode = findBlock(targetSection.blocks, target.block);
  if (position === 'inside' && targetNode && !canContain(targetNode)) return false;
  sourceLocation.list.splice(sourceLocation.index, 1);
  if (position === 'inside' && targetNode) {
    (targetNode.children ||= []).push(node);
  } else if (target.block) {
    const destination = findBlockLocation(targetSection.blocks, target.block);
    if (!destination) {
      sourceLocation.list.splice(sourceLocation.index, 0, node);
      return false;
    }
    destination.list.splice(destination.index + (position === 'after' ? 1 : 0), 0, node);
  } else {
    targetSection.blocks.push(node);
  }
  return true;
}
