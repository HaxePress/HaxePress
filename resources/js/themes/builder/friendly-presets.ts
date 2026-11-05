import { contentRepeater, layoutBlock } from './presets';
import {
  newBlock,
  newSection,
  upgradeDocument,
  visitBlocks,
  type DesignBlock,
  type BlockType,
  type DesignSection,
  type ThemeDocument,
} from './types';

export const starterChoices = [
  {
    id: 'business',
    name: 'Business',
    description: 'Introduce what you do and help people get in touch.',
  },
  {
    id: 'portfolio',
    name: 'Portfolio',
    description: 'Show your work with images and a simple introduction.',
  },
  {
    id: 'journal',
    name: 'News and articles',
    description: 'Share updates using content already in your CMS.',
  },
  {
    id: 'blank',
    name: 'Blank page',
    description: 'Start with an empty page and add your own sections.',
  },
] as const;
export type StarterChoice = (typeof starterChoices)[number]['id'];
export const paletteChoices = [
  { name: 'Blue', value: '#405bcc', soft: '#eff3ff' },
  { name: 'Forest', value: '#2f6c57', soft: '#edf6f0' },
  { name: 'Violet', value: '#7452a1', soft: '#f4effa' },
  { name: 'Clay', value: '#b76035', soft: '#fbf1eb' },
] as const;
export const sectionChoices = [
  {
    id: 'welcome',
    name: 'Introduction',
    description: 'A title, a short message and a button.',
    art: 'intro',
  },
  {
    id: 'split',
    name: 'Image and text',
    description: 'Put a photo beside your message.',
    art: 'split',
  },
  {
    id: 'highlights',
    name: 'Highlights',
    description: 'Three simple cards for services or ideas.',
    art: 'cards',
  },
  {
    id: 'content',
    name: 'Latest content',
    description: 'Show published content automatically.',
    art: 'content',
  },
  {
    id: 'callout',
    name: 'Call to action',
    description: 'A message with one clear next step.',
    art: 'callout',
  },
  {
    id: 'questions',
    name: 'Questions and answers',
    description: 'Answers that visitors can open and close.',
    art: 'questions',
  },
  {
    id: 'contact',
    name: 'Contact details',
    description: 'A place for your address and contact information.',
    art: 'contact',
  },
  {
    id: 'empty',
    name: 'Empty section',
    description: 'Add a title, text or image yourself.',
    art: 'empty',
  },
] as const;
export type FriendlySection = (typeof sectionChoices)[number]['id'] | 'header' | 'footer';

function textBlock(type: 'heading' | 'text', text: string, level = 2): DesignBlock {
  const node = newBlock(type);
  node.text = text;
  node.level = level;
  return node;
}
function container(
  name: string,
  children: DesignBlock[],
  styles: Record<string, string> = {},
): DesignBlock {
  const node = newBlock('container');
  node.name = name;
  node.children = children;
  node.styles = {
    desktop: { normal: { display: 'flex', 'flex-direction': 'column', gap: '20px', ...styles } },
  };
  return node;
}
export function friendlySection(kind: FriendlySection): DesignSection {
  const label =
    sectionChoices.find((choice) => choice.id === kind)?.name ||
    (kind === 'header' ? 'Header' : 'Footer');
  const section = newSection(label);
  if (kind === 'welcome') {
    const hero = layoutBlock('hero');
    hero.name = 'Introduction';
    hero.styles!.desktop!.normal!.background = 'var(--friendly-surface, #eff3ff)';
    hero.styles!.desktop!.normal!['min-height'] = '420px';
    hero.children![0].text = 'Your title goes here';
    hero.children![1].text = 'Write a short introduction for your visitors.';
    hero.children![2].text = 'Learn more';
    hero.children![2].href = '/about';
    section.blocks = [hero];
  }
  if (kind === 'split') {
    const split = layoutBlock('split');
    split.children![1].children![0].text = 'Tell your story';
    split.children![1].children![1].text =
      'Add a few words about your work, your business or your ideas.';
    split.children![1].children![2].href = '/about';
    section.blocks = [split];
  }
  if (kind === 'highlights') {
    const grid = layoutBlock('grid');
    grid.name = 'Highlights';
    grid.children = Array.from({ length: 3 }, (_, index) =>
      container(
        'Highlight ' + (index + 1),
        [
          textBlock('heading', 'Highlight ' + (index + 1), 3),
          textBlock('text', 'Describe one thing your visitors should know.'),
        ],
        { padding: '28px', background: '#f5f7fb', 'border-radius': '12px' },
      ),
    );
    section.blocks = [textBlock('heading', 'What you offer'), grid];
  }
  if (kind === 'content')
    section.blocks = [textBlock('heading', 'Latest content'), contentRepeater()];
  if (kind === 'callout') {
    const button = newBlock('button');
    button.text = 'Find out more';
    button.href = '/about';
    section.blocks = [
      container(
        'Call to action',
        [
          textBlock('heading', 'Add your message'),
          textBlock('text', 'Give your visitors one clear next step.'),
          button,
        ],
        {
          padding: '48px',
          background: 'var(--friendly-surface, #eff3ff)',
          'border-radius': '16px',
          'align-items': 'center',
          'text-align': 'center',
        },
      ),
    ];
  }
  if (kind === 'questions') {
    section.blocks = [
      textBlock('heading', 'Questions and answers'),
      ...Array.from({ length: 3 }, (_, index) => {
        const details = newBlock('element');
        details.tag = 'details';
        details.name = 'Question ' + (index + 1);
        details.styles = {
          desktop: { normal: { padding: '20px 0', 'border-bottom': '1px solid #dfe5ee' } },
        };
        const summary = newBlock('element');
        summary.tag = 'summary';
        summary.text = 'Add your question';
        summary.styles = { desktop: { normal: { cursor: 'pointer', 'font-weight': '600' } } };
        details.children = [summary, textBlock('text', 'Write the answer here.')];
        return details;
      }),
    ];
  }
  if (kind === 'contact')
    section.blocks = [
      textBlock('heading', 'Contact'),
      textBlock('text', 'Add your contact details, address or opening hours.'),
    ];
  if (kind === 'empty')
    section.blocks = [
      textBlock('heading', 'Your section title'),
      textBlock('text', 'Add your text here.'),
    ];
  if (kind === 'header') {
    section.padding = 24;
    section.columns = 2;
    section.blocks = [newBlock('brand'), newBlock('navigation')];
  }
  if (kind === 'footer') {
    section.padding = 32;
    section.blocks = [newBlock('navigation')];
  }
  return section;
}
export function friendlyDocument(
  base: ThemeDocument,
  choice: StarterChoice,
  accent: string,
  font: string,
): ThemeDocument {
  const document = upgradeDocument(base);
  document.tokens = {
    ...document.tokens,
    accent,
    font,
    width: 1120,
    radius: 12,
    background: '#ffffff',
    text: '#1d2939',
  };
  document.header = [friendlySection('header')];
  document.footer = [friendlySection('footer')];
  const sections: Record<StarterChoice, FriendlySection[]> = {
    business: ['welcome', 'highlights', 'contact'],
    portfolio: ['split', 'highlights', 'contact'],
    journal: ['welcome', 'content'],
    blank: [],
  };
  document.templates.Home = sections[choice].map(friendlySection);
  const soft = paletteChoices.find((palette) => palette.value === accent)?.soft || '#eff3ff';
  document.css = (document.css || '') + '\n:scope { --friendly-surface: ' + soft + '; }';
  return document;
}
export function friendlyLabel(node: DesignBlock): string {
  if (node.type === 'heading' || (node.type === 'element' && /^h[1-6]$/.test(node.tag || '')))
    return 'Heading';
  if (
    node.type === 'text' ||
    (node.type === 'element' && ['p', 'span', 'summary'].includes(node.tag || ''))
  )
    return 'Text';
  if (node.type === 'image' || node.type === 'content-image') return 'Image';
  if (node.type === 'button') return 'Button';
  if (node.type === 'brand') return 'Site name and logo';
  if (node.type === 'navigation') return 'Menu';
  if (node.type === 'repeat' || node.type === 'content-list') return 'Your content';
  if (node.type === 'component') return 'Saved part';
  if (node.type === 'content-title') return 'Content title';
  if (node.type === 'content-body') return 'Content body';
  return node.name || friendlyBlockLabels[node.type];
}
export const friendlyBlockLabels: Record<BlockType, string> = {
  container: 'Group',
  element: 'Custom element',
  heading: 'Heading',
  text: 'Text',
  image: 'Image',
  button: 'Button',
  spacer: 'Empty space',
  divider: 'Divider',
  brand: 'Site name and logo',
  navigation: 'Menu',
  repeat: 'Content cards',
  component: 'Saved part',
  extension: 'Plugin area',
  pagination: 'Page numbers',
  search: 'Search and filters',
  'content-list': 'Content list',
  'content-title': 'Content title',
  'content-excerpt': 'Content summary',
  'content-image': 'Content image',
  'content-body': 'Content body',
  'site-description': 'Site description',
};
export function editableText(node: DesignBlock): boolean {
  return (
    !node.bindings?.text &&
    !node.children?.length &&
    (['heading', 'text', 'button'].includes(node.type) ||
      (node.type === 'element' &&
        [
          'h1',
          'h2',
          'h3',
          'h4',
          'h5',
          'h6',
          'p',
          'span',
          'strong',
          'em',
          'small',
          'summary',
        ].includes(node.tag || '')))
  );
}
export function firstEditable(section: DesignSection): DesignBlock | undefined {
  let result: DesignBlock | undefined;
  visitBlocks(section.blocks, (node) => {
    if (!result && (editableText(node) || node.type === 'image')) result = node;
  });
  return result;
}
