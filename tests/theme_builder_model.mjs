import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import ts from 'typescript';

async function compiled(name) {
  const source = await readFile(
    new URL(`../resources/js/themes/builder/${name}.ts`, import.meta.url),
    'utf8',
  );
  return ts.transpileModule(source, {
    compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ES2022 },
  }).outputText;
}
const typesCode = await compiled('types');
const typesUrl = `data:text/javascript;base64,${Buffer.from(typesCode).toString('base64')}`;
const {
  moveDesignEntry,
  templateNames,
  findBlock,
  findBlockLocation,
  cloneBlock,
  setStyle,
  upgradeDocument,
  newBlock,
} = await import(typesUrl);
const stylesCode = (await compiled('styles')).replace(
  /from ['"]\.\/types['"]/g,
  `from ${JSON.stringify(typesUrl)}`,
);
const { designStyles } = await import(
  `data:text/javascript;base64,${Buffer.from(stylesCode).toString('base64')}`
);
const controlsCode = (await compiled('easy-controls')).replace(
  /from ['"]\.\/types['"]/g,
  `from ${JSON.stringify(typesUrl)}`,
);
const { templateIdentifier, effectiveStyles } = await import(
  `data:text/javascript;base64,${Buffer.from(controlsCode).toString('base64')}`
);
const bindingCode = await compiled('bindings');
const { bindingValue, isVisible, linkValue, imageValue } = await import(
  `data:text/javascript;base64,${Buffer.from(bindingCode).toString('base64')}`
);
function node(id, children = []) {
  return { id, type: 'container', text: '', href: '', image: '', alt: '', level: 2, children };
}
function section(id, blocks = []) {
  return {
    id,
    name: id,
    blocks,
    padding: 0,
    align: 'left',
    width: 'full',
    columns: 1,
    background: '',
    color: '',
  };
}
const document = {
  schema: 1,
  tokens: {
    background: '#ffffff',
    text: '#000000',
    accent: '#405bcc',
    font: 'sans',
    width: 1120,
    radius: 8,
  },
  header: [],
  footer: [],
  templates: Object.fromEntries(templateNames.map((name) => [name, []])),
};
document.templates.Home = [
  section('intro', [node('row', [node('heading'), node('text')])]),
  section('content', [node('list')]),
  section('closing'),
];
assert.equal(
  moveDesignEntry(
    document,
    { scope: 'Home', section: 'closing' },
    { scope: 'Home', section: 'intro' },
  ),
  true,
);
assert.deepEqual(
  document.templates.Home.map((section) => section.id),
  ['closing', 'intro', 'content'],
);
assert.equal(
  moveDesignEntry(
    document,
    { scope: 'Home', section: 'intro', block: 'heading' },
    { scope: 'Home', section: 'content', block: 'list', position: 'inside' },
  ),
  true,
);
assert.equal(findBlock(document.templates.Home[2].blocks, 'list').children[0].id, 'heading');
assert.equal(findBlock(document.templates.Home[1].blocks, 'row').children.length, 1);
assert.equal(
  moveDesignEntry(
    document,
    { scope: 'Home', section: 'content', block: 'list' },
    { scope: 'Home', section: 'content', block: 'heading', position: 'inside' },
  ),
  false,
  'A node moved into its descendant',
);
assert.equal(
  moveDesignEntry(
    document,
    { scope: 'Home', section: 'intro', block: 'row' },
    { scope: 'Home', section: 'content', block: 'list', position: 'after' },
  ),
  true,
);
assert.deepEqual(
  document.templates.Home[2].blocks.map((node) => node.id),
  ['list', 'row'],
);
assert.equal(findBlockLocation(document.templates.Home[2].blocks, 'text').parent.id, 'row');
moveDesignEntry(document, { scope: 'Home', section: 'closing' }, { scope: 'header', section: '' });
assert.equal(document.header[0].id, 'closing');
moveDesignEntry(
  document,
  { scope: 'Home', section: 'intro' },
  { scope: 'Home', section: '', position: 'after' },
);
assert.deepEqual(
  document.templates.Home.map((section) => section.id),
  ['content', 'intro'],
);
const before = structuredClone(document);
assert.equal(
  moveDesignEntry(
    document,
    { scope: 'Home', section: 'missing' },
    { scope: 'Home', section: 'content' },
  ),
  false,
);
assert.equal(
  moveDesignEntry(
    document,
    { scope: 'unknown', section: 'missing' },
    { scope: 'Home', section: 'content' },
  ),
  false,
);
assert.deepEqual(document, before);
const voidElement = newBlock('element');
voidElement.tag = 'input';
document.templates.Home[0].blocks.push(voidElement);
const beforeVoidMove = structuredClone(document);
assert.equal(
  moveDesignEntry(
    document,
    { scope: 'Home', section: 'content', block: 'row' },
    { scope: 'Home', section: 'content', block: voidElement.id, position: 'inside' },
  ),
  false,
  'A move inserted children into a void element',
);
assert.deepEqual(document, beforeVoidMove, 'Rejected move removed or changed existing nodes');
const original = node('a', [node('b', [node('c')])]);
const copy = cloneBlock(original);
assert.notEqual(copy.id, original.id);
assert.notEqual(copy.children[0].children[0].id, 'c');
const upgraded = upgradeDocument(document);
assert.equal(upgraded.schema, 2);
assert.equal(document.schema, 1, 'Upgrading mutated the stored legacy document');
upgraded.classes.card = {
  desktop: { normal: { 'border-radius': '24px' }, hover: { transform: 'translateY(-4px)' } },
  mobile: { normal: { display: 'block' } },
};
upgraded.templates.Home[0].styles = {};
setStyle(upgraded.templates.Home[0].styles, 'mobile', 'normal', 'display', 'flex');
setStyle(upgraded.templates.Home[0].styles, 'mobile', 'hover', 'color', '#ff0000');
upgraded.css = '.card::before { content: "Hello"; }';
const css = designStyles(upgraded);
assert.ok(css.includes('@media(max-width:600px)'));
assert.ok(css.includes(':hover{transform:translateY(-4px)'));
assert.ok(css.includes('@scope (.hp-design)'));

// The cascade: every desktop rule, then one tablet and one mobile block, classes before nodes.
const cascade = structuredClone(upgraded);
cascade.css = '';
cascade.classes = {
  split: { desktop: { normal: { 'flex-direction': 'row', display: 'flex' } } },
  collapse: {
    desktop: { normal: { gap: '24px' } },
    tablet: { normal: { gap: '16px' } },
    mobile: { normal: { 'flex-direction': 'column', padding: '16px' } },
  },
};
const row = newBlock('container');
row.classes = ['split', 'collapse'];
row.styles = {
  desktop: { normal: { padding: '48px' } },
  mobile: { normal: { gap: '8px' } },
};
cascade.templates.Home[0].blocks.push(row);
const cascadeCss = designStyles(cascade);
const rowSelector = `.hp-design [data-design-node="${row.id}"]`;
const tabletStart = cascadeCss.indexOf('@media(max-width:900px){');
const mobileStart = cascadeCss.indexOf('@media(max-width:600px){');
assert.equal(cascadeCss.split('@media(max-width:900px)').length, 2, 'Tablet rules were split up');
assert.equal(cascadeCss.split('@media(max-width:600px)').length, 2, 'Mobile rules were split up');
const collapseDesktop = cascadeCss.indexOf('.hp-design .design-class-collapse{gap:24px;}');
const splitDesktop = cascadeCss.indexOf(
  '.hp-design .design-class-split{display:flex;flex-direction:row;}',
);
const rowDesktop = cascadeCss.indexOf(`${rowSelector}{padding:48px;}`);
const collapseMobile = cascadeCss.indexOf(
  '.hp-design .design-class-collapse{flex-direction:column;padding:16px;}',
);
const rowMobile = cascadeCss.indexOf(`${rowSelector}{gap:8px;}`);
assert.ok(
  collapseDesktop >= 0 && collapseDesktop < splitDesktop,
  'Classes were not written in name order with sorted properties',
);
assert.ok(
  splitDesktop < rowDesktop && rowDesktop < tabletStart,
  'Desktop rules did not precede the tablet block, classes before nodes',
);
assert.ok(
  tabletStart < mobileStart && mobileStart < collapseMobile && collapseMobile < rowMobile,
  "A class's mobile rule did not follow another class's and the node's desktop rules",
);
assert.equal(templateIdentifier('Contact us', upgraded), 'ContactUs');
assert.equal(templateIdentifier('Home', upgraded), 'Home2');
assert.equal(templateIdentifier('123', upgraded), 'PageLayout123');
assert.equal(templateIdentifier('Admin settings', upgraded), 'PageLayoutAdminSettings');
assert.match(templateIdentifier('İletişim', upgraded), /^[A-Za-z][A-Za-z0-9_-]{0,79}$/);
const responsive = newBlock('container');
responsive.classes = ['card'];
responsive.styles = {
  desktop: { normal: { width: '80%', 'font-size': '48px' }, hover: { opacity: '0.8' } },
  tablet: { normal: { 'font-size': '32px' } },
  mobile: { normal: { width: '100%' }, hover: { opacity: '0.6' } },
};
const untouchedStyles = structuredClone(responsive.styles);
assert.deepEqual(effectiveStyles(upgraded, responsive, 'mobile', 'hover'), {
  'border-radius': '24px',
  display: 'block',
  width: '100%',
  'font-size': '32px',
  transform: 'translateY(-4px)',
  opacity: '0.6',
});
assert.equal(effectiveStyles(upgraded, responsive, 'desktop', 'normal').width, '80%');
assert.equal(effectiveStyles(upgraded, responsive, 'mobile', 'normal').opacity, undefined);
assert.deepEqual(responsive.styles, untouchedStyles, 'Reading appearance rewrote stored overrides');
const decorated = newBlock('heading');
decorated.attributes = { 'data-kind': 'title' };
const described = newBlock('element');
described.attributes = { 'aria-label': 'Kept' };
const withAttributes = structuredClone(upgraded);
withAttributes.templates.Home[0].blocks.push(decorated, described);
const cleaned = upgradeDocument(withAttributes);
assert.deepEqual(
  findBlock(cleaned.templates.Home[0].blocks, decorated.id).attributes,
  {},
  'Upgrading kept attributes the server rejects on a heading',
);
assert.deepEqual(findBlock(cleaned.templates.Home[0].blocks, described.id).attributes, {
  'aria-label': 'Kept',
});
assert.deepEqual(decorated.attributes, { 'data-kind': 'title' }, 'Upgrading mutated its input');
const context = {
  site: { site_name: 'Example' },
  item: { title: 'Bound title', image: '' },
  collection: {},
  page: { count: 3 },
};
assert.equal(bindingValue(context, 'item.title'), 'Bound title');
assert.equal(
  bindingValue(
    { ...context, item: { ...context.item, fields: { price: 12.5 } } },
    'item.fields.price',
  ),
  12.5,
);
assert.equal(bindingValue(context, 'item.__proto__.title'), '');
assert.equal(bindingValue(context, 'auth.admin.email'), '');
assert.equal(bindingValue(context, 'item.constructor'), '');
assert.equal(
  isVisible({ condition: { field: 'item.image', operator: 'present', value: '' } }, context),
  false,
);
assert.equal(
  isVisible(
    { condition: { field: 'item.title', operator: 'equals', value: 'Bound title' } },
    context,
  ),
  true,
);
assert.equal(linkValue('javascript:alert(1)'), '');
assert.equal(linkValue('//example.test/redirect'), '');
assert.equal(linkValue('/content/item'), '/content/item');
assert.equal(imageValue('https://example.test/image.jpg', '^/media/[A-Za-z0-9_-]+\\.jpg$'), '');
console.log(
  'PASS Composable design: nested moves, cycle prevention, cross-scope/end drops, deep cloning, legacy upgrade, responsive/hover CSS and cascade order, element-only attributes, safe and custom-field bindings and visibility',
);
