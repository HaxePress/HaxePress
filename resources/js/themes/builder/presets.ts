import { newBlock, newSection, type DesignBlock, type DesignSection } from './types';

function styled(type: DesignBlock['type'], properties: Record<string, string>): DesignBlock {
  const block = newBlock(type);
  block.styles = { desktop: { normal: properties } };
  return block;
}
export function contentRepeater(): DesignBlock {
  const repeat = styled('repeat', {
    display: 'grid',
    'grid-template-columns': 'repeat(3, minmax(0, 1fr))',
    gap: '32px',
  });
  repeat.name = 'Content cards';
  repeat.styles!.tablet = { normal: { 'grid-template-columns': 'repeat(2, minmax(0, 1fr))' } };
  repeat.styles!.mobile = { normal: { 'grid-template-columns': 'minmax(0, 1fr)' } };
  const card = styled('container', { display: 'flex', 'flex-direction': 'column', gap: '16px' });
  card.name = 'Card';
  const image = styled('image', {
    width: '100%',
    'aspect-ratio': '1.5',
    'object-fit': 'cover',
    'border-radius': '8px',
  });
  image.bindings = { image: 'item.image', alt: 'item.image_alt', href: 'item.url' };
  image.condition = { field: 'item.image', operator: 'present', value: '' };
  const heading = styled('heading', { 'font-size': '24px', 'line-height': '1.2' });
  heading.level = 2;
  heading.bindings = { text: 'item.title', href: 'item.url' };
  const excerpt = styled('text', { 'font-size': '15px', 'line-height': '1.65' });
  excerpt.bindings = { text: 'item.excerpt' };
  const date = styled('element', { 'font-size': '12px', opacity: '0.65' });
  date.tag = 'time';
  date.bindings = { text: 'item.publishedLabel', datetime: 'item.published_at' };
  card.children = [image, heading, excerpt, date];
  repeat.children = [card];
  return repeat;
}
export const layoutPresets = {
  container: 'Container',
  row: 'Row',
  column: 'Column',
  grid: 'Grid',
  hero: 'Hero',
  split: 'Image and text',
  cards: 'Content cards',
  spacer: 'Space',
} as const;
export function layoutBlock(preset: keyof typeof layoutPresets): DesignBlock {
  if (preset === 'cards') return contentRepeater();
  if (preset === 'spacer') return newBlock('spacer');
  const node = styled('container', { display: 'flex', 'flex-direction': 'column', gap: '24px' });
  node.name = layoutPresets[preset];
  if (preset === 'row' || preset === 'split') {
    node.styles!.desktop!.normal!['flex-direction'] = 'row';
    node.styles!.desktop!.normal!['align-items'] = 'center';
    node.styles!.mobile = { normal: { 'flex-direction': 'column', 'align-items': 'stretch' } };
  }
  if (preset === 'grid') {
    node.styles!.desktop!.normal = {
      display: 'grid',
      'grid-template-columns': 'repeat(3, minmax(0, 1fr))',
      gap: '24px',
    };
    node.styles!.tablet = { normal: { 'grid-template-columns': 'repeat(2, minmax(0, 1fr))' } };
    node.styles!.mobile = { normal: { 'grid-template-columns': 'minmax(0, 1fr)' } };
    node.children = Array.from({ length: 3 }, () =>
      styled('container', { 'min-height': '120px', padding: '24px', background: '#f4f6fa' }),
    );
  }
  if (preset === 'hero') {
    node.styles!.desktop!.normal = {
      display: 'flex',
      'flex-direction': 'column',
      'justify-content': 'center',
      'align-items': 'flex-start',
      gap: '24px',
      'min-height': '65vh',
      padding: 'clamp(32px, 6vw, 100px)',
      background: '#eff3fa',
      'border-radius': '16px',
    };
    const heading = newBlock('heading');
    heading.level = 1;
    heading.styles = {
      desktop: {
        normal: {
          'font-size': 'clamp(40px, 6vw, 80px)',
          'max-width': '16ch',
          'line-height': '1.05',
        },
      },
    };
    const text = newBlock('text');
    text.styles = { desktop: { normal: { 'max-width': '60ch', 'font-size': '18px' } } };
    node.children = [heading, text, newBlock('button')];
  }
  if (preset === 'split') {
    const image = newBlock('image');
    image.styles = {
      desktop: { normal: { width: '50%', 'border-radius': '12px' } },
      mobile: { normal: { width: '100%' } },
    };
    const column = layoutBlock('column');
    column.styles!.desktop!.normal!.flex = '1';
    column.children = [newBlock('heading'), newBlock('text'), newBlock('button')];
    node.children = [image, column];
  }
  return node;
}
export function layoutSection(preset: keyof typeof layoutPresets): DesignSection {
  const section = newSection(layoutPresets[preset]);
  section.blocks = [layoutBlock(preset)];
  return section;
}
