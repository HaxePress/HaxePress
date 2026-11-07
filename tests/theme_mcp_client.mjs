import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { Client, StreamableHTTPClientTransport } from '@modelcontextprotocol/client';
import { build } from 'esbuild';
import * as z from 'zod/v4';

// The visual editor's ready sections, layouts and blocks, which the site's MCP tools port.
const bundle = await build({
  stdin: {
    contents: `export { friendlySection, sectionChoices } from './resources/js/themes/builder/friendly-presets';
      export { layoutBlock, layoutPresets } from './resources/js/themes/builder/presets';
      export { blockLabels, newBlock } from './resources/js/themes/builder/types';`,
    resolveDir: fileURLToPath(new URL('../', import.meta.url)),
    sourcefile: 'preset-parity.ts',
    loader: 'ts',
  },
  bundle: true,
  write: false,
  platform: 'node',
  format: 'esm',
});
const editorPresets = await import(
  `data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString('base64')}`
);

/**
 * The MCP edit operations build the same ready sections, layouts and blocks as
 * the editor: both are saved through the CMS validation and compared without
 * their random IDs.
 */
async function verifyPresets(call, data, version) {
  const scope = 'PresetParity';
  const base = data(await call('get_design')).theme.document;
  base.templates[scope] = [];
  base.templateMeta[scope] = { label: 'Preset parity', fallback: 'Page' };
  let saved = data(await call('replace_design', { expectedVersion: version, document: base }));
  const kinds = [...editorPresets.sectionChoices.map((choice) => choice.id), 'header', 'footer'];
  saved = data(
    await call('edit_design', {
      expectedVersion: saved.version,
      operations: kinds.map((preset) => ({
        action: 'section',
        target: { scope, section: '' },
        preset,
      })),
    }),
  );
  const host = saved.created.at(-1).section;
  const blocks = [
    ...Object.keys(editorPresets.layoutPresets).map((id) => `layout:${id}`),
    // A component block needs a reusable component to render, so the CMS refuses an empty one.
    ...Object.keys(editorPresets.blockLabels).filter((type) => type !== 'component'),
  ];
  saved = data(
    await call('edit_design', {
      expectedVersion: saved.version,
      operations: blocks.map((preset) => ({
        action: 'insert',
        target: { scope, section: host },
        preset,
      })),
    }),
  );
  const native = data(await call('get_design')).theme.document;
  const document = structuredClone(native);
  document.templates[scope] = kinds.map((kind) => editorPresets.friendlySection(kind));
  document.templates[scope]
    .at(-1)
    .blocks.push(
      ...blocks.map((preset) =>
        preset.startsWith('layout:')
          ? editorPresets.layoutBlock(preset.slice(7))
          : editorPresets.newBlock(preset),
      ),
    );
  saved = data(await call('replace_design', { expectedVersion: saved.version, document }));
  const editor = data(await call('get_design')).theme.document;
  const withoutIds = (value) =>
    JSON.parse(JSON.stringify(value, (key, entry) => (key === 'id' ? undefined : entry)));
  assert.deepEqual(
    withoutIds(native.templates[scope]),
    withoutIds(editor.templates[scope]),
    'The MCP presets differ from the editor presets',
  );
  delete editor.templates[scope];
  delete editor.templateMeta[scope];
  saved = data(await call('replace_design', { expectedVersion: saved.version, document: editor }));
  return saved.version;
}

const environment = {
  HXPRESS_THEME_ID: process.env.TEST_THEME_ID,
};
const credentials = {
  Authorization: `Bearer ${process.env.TEST_MCP_TOKEN}`,
};
const globalNames = {
  get_design_guide: 'get_theme_design_guide',
  get_design: 'get_theme_design',
  edit_design: 'edit_theme_design',
  replace_design: 'replace_theme_design',
  search_media: 'search_media_for_theme',
  get_collection_schema: 'get_theme_collection_schema',
  read_media_image: 'read_media_for_theme',
  preview_theme: 'preview_theme_design',
};
const skillUri = 'skill://haxepress-theme-design/SKILL.md';
const skillEntry = z.looseObject({
  uri: z.string(),
  frontmatter: z.looseObject({ name: z.string(), description: z.string() }),
  resources: z.array(z.object({ uri: z.string(), digest: z.string(), size: z.number() })),
});

/**
 * The theme design skill reaches every client: through the skills extension
 * (SEP-2640), as resources, through a read-only tool and as a prompt.
 */
async function verifySkill(client, names) {
  assert.ok(client.getServerCapabilities()?.extensions?.['io.modelcontextprotocol/skills']);
  assert.ok(
    client.getInstructions()?.includes(skillUri),
    'The instructions do not point at the skill',
  );
  const { skills } = await client.request(
    { method: 'skills/list', params: {} },
    z.looseObject({ skills: z.array(skillEntry) }),
  );
  const skill = skills.find((entry) => entry.uri === skillUri);
  assert.equal(skill.frontmatter.name, 'haxepress-theme-design');
  assert.ok(skill.frontmatter.description.length > 100);
  assert.ok(skill.resources.some((file) => file.uri === skillUri));
  const texts = [];
  for (const file of skill.resources) {
    const { contents } = await client.readResource({ uri: file.uri });
    const bytes = Buffer.from(contents[0].text, 'utf8');
    assert.equal(contents[0].mimeType, 'text/markdown', file.uri);
    assert.equal(bytes.length, file.size, file.uri);
    assert.equal(
      `sha256:${createHash('sha256').update(bytes).digest('hex')}`,
      file.digest,
      file.uri,
    );
    texts.push(contents[0].text);
  }
  const { skill: fetched } = await client.request(
    { method: 'skills/get', params: { uri: skillUri } },
    z.looseObject({ skill: skillEntry }),
  );
  assert.deepEqual(fetched, skill);
  await assert.rejects(
    client.request(
      { method: 'skills/get', params: { uri: 'skill://other/SKILL.md' } },
      z.looseObject({}),
    ),
    (error) => error.code === -32602,
  );
  const main = texts[skill.resources.findIndex((file) => file.uri === skillUri)];
  assert.ok(main.startsWith('---\nname: haxepress-theme-design\n'));
  const tool = await client.callTool({ name: 'get_theme_design_skill', arguments: {} });
  assert.equal(tool.content[0].text, main);
  const reference = await client.callTool({
    name: 'get_theme_design_skill',
    arguments: { file: 'references/visual-review.md' },
  });
  assert.ok(reference.content[0].text.startsWith('# Reviewing a design'));
  const brief = 'A calm site for a ceramics studio.';
  const prompt = await client.getPrompt({ name: 'design_theme', arguments: { brief } });
  const message = prompt.messages[0].content.text;
  assert.ok(message.includes(brief) && message.includes('# Designing HaxePress themes'));
  // Every tool the skill names exists, under its admin name or its theme connection name.
  const tools =
    /`((?:get|list|create|edit|replace|preview|search|read|upload|verify|set|inspect)_[a-z_]+)`/g;
  for (const [, name] of texts.join('\n').matchAll(tools))
    assert.ok(
      names.has(name) || names.has(globalNames[name]),
      `The skill names a missing tool: ${name}`,
    );
}

let latestVersion;
for (const mode of ['legacy', { pin: '2026-07-28' }]) {
  const client = new Client(
    { name: 'haxepress-integration', version: '1.0.0' },
    {
      versionNegotiation: { mode },
    },
  );
  const transport = new StreamableHTTPClientTransport(new URL(process.env.TEST_MCP_URL), {
    requestInit: { headers: credentials },
  });
  async function call(name, args = {}) {
    const argumentsWithTheme =
      name === 'get_design_guide' ? args : { themeId: environment.HXPRESS_THEME_ID, ...args };
    return client.callTool({ name: globalNames[name] || name, arguments: argumentsWithTheme });
  }
  function data(value) {
    assert.ok(!value.isError, value.content?.[0]?.text);
    return value.structuredContent || JSON.parse(value.content[0].text);
  }
  try {
    await client.connect(transport);
    if (client.getProtocolEra() === 'modern') await client.discover();
    else await client.ping();
    const { tools } = await client.listTools();
    const names = new Set(tools.map((tool) => tool.name));
    for (const name of [
      ...Object.values(globalNames),
      'inspect_theme_tree',
      'get_theme_section',
      'search_theme_assets',
      'read_theme_asset_image',
      'upload_theme_image',
      'verify_theme_image',
      'set_theme_block_image',
    ])
      assert.ok(names.has(name), name);
    assert.ok(!names.has('publish_theme') && !names.has('activate_theme'));
    const guide = data(await call('get_design_guide'));
    assert.equal(guide.schema, 2);
    assert.equal(guide.limits.nodes, 2048);
    const resources = await client.listResources();
    assert.equal(resources.resources[0].uri, 'haxepress://theme/design-guide');
    const read = await client.readResource({ uri: 'haxepress://theme/design-guide' });
    assert.equal(JSON.parse(read.contents[0].text).schema, 2);
    await verifySkill(client, names);
    const missing = await client.callTool({
      name: 'get_theme_design',
      arguments: { themeId: 'theme-does-not-exist' },
    });
    assert.ok(
      missing.isError && missing.content[0].text.includes('list_themes'),
      missing.content[0].text,
    );
    let snapshot = data(await call('get_design'));
    const collection = data(
      await call('get_collection_schema', { key: snapshot.collections[0].key }),
    );
    assert.ok(Array.isArray(collection.collection.fields));
    const before = snapshot.theme.version;
    assert.equal(snapshot.theme.id, environment.HXPRESS_THEME_ID);
    let saved = data(
      await call('edit_design', {
        expectedVersion: before,
        operations: [
          {
            action: 'section',
            target: { scope: 'Home', section: '' },
            preset: 'welcome',
            name: 'AI introduction',
          },
        ],
      }),
    );
    const section = saved.created[0].section;
    assert.equal(saved.version, before + 1);
    snapshot = data(await call('get_design'));
    const heading = snapshot.theme.document.templates.Home.find((entry) => entry.id === section)
      .blocks[0].children[0];
    saved = data(
      await call('edit_design', {
        expectedVersion: snapshot.theme.version,
        operations: [
          {
            action: 'update',
            target: { scope: 'Home', section, block: heading.id },
            values: { text: 'Designed through MCP' },
          },
          {
            action: 'style',
            target: { scope: 'Home', section, block: heading.id },
            breakpoint: 'mobile',
            values: { 'font-size': '34px' },
          },
          { action: 'tokens', values: { accent: '#225599' } },
        ],
      }),
    );
    assert.equal(saved.version, before + 2);
    const stale = await call('edit_design', {
      expectedVersion: before,
      operations: [{ action: 'tokens', values: { accent: '#ff0000' } }],
    });
    assert.equal(stale.isError, true);
    const invalid = await call('edit_design', {
      expectedVersion: saved.version,
      operations: [
        { action: 'tokens', values: { accent: '#ff0000' } },
        {
          action: 'move',
          target: { scope: 'Home', section, block: heading.id },
          destination: { scope: 'Home', section, block: heading.id, position: 'inside' },
        },
      ],
    });
    assert.equal(invalid.isError, true);
    snapshot = data(await call('get_design'));
    assert.equal(snapshot.theme.version, saved.version);
    assert.equal(snapshot.theme.document.tokens.accent, '#225599');
    assert.equal(
      snapshot.theme.document.templates.Home.find((entry) => entry.id === section).blocks[0]
        .children[0].styles.mobile.normal['font-size'],
      '34px',
    );
    const scoped = data(await call('get_design', { scope: 'Home' }));
    assert.equal(
      scoped.sections.find((entry) => entry.id === section).blocks[0].children[0].text,
      'Designed through MCP',
    );
    assert.equal(scoped.document, undefined);
    // The AI looks at its saved draft: the whole home page on a phone, then a missing page.
    const look = await call('preview_theme', { path: '/', device: 'mobile', fullPage: true });
    assert.ok(!look.isError, look.content?.[0]?.text);
    assert.ok(
      look.content.some(
        (item) =>
          item.type === 'image' && item.mimeType === 'image/jpeg' && item.data.length > 1000,
      ),
    );
    assert.equal(look.structuredContent.status, 200);
    assert.ok(
      look.structuredContent.headings.includes('Designed through MCP'),
      JSON.stringify(look.structuredContent.headings),
    );
    assert.ok(look.structuredContent.links.some((link) => link.path.startsWith('/content')));
    const missingPage = data(await call('preview_theme', { path: '/no-such-page' }));
    assert.equal(missingPage.status, 404);
    const replacement = structuredClone(snapshot.theme.document);
    replacement.templates.AIPage = [];
    replacement.templateMeta.AIPage = { label: 'AI page', fallback: 'Page' };
    saved = data(
      await call('replace_design', {
        expectedVersion: saved.version,
        name: 'MCP generated draft',
        document: replacement,
      }),
    );
    snapshot = data(await call('get_design'));
    assert.equal(snapshot.theme.document.templateMeta.AIPage.label, 'AI page');
    const invalidDocument = structuredClone(snapshot.theme.document);
    invalidDocument.templates.Home[0].blocks[0].href = 'javascript:alert(1)';
    assert.equal(
      (
        await call('replace_design', {
          expectedVersion: saved.version,
          document: invalidDocument,
        })
      ).isError,
      true,
    );
    const media = data(await call('search_media', { query: '' }));
    assert.ok(media.items.length > 0 && media.items.length <= 24);
    const image = await call('read_media_image', {
      id: Number(process.env.TEST_MCP_IMAGE_ID),
    });
    assert.ok(!image.isError);
    assert.equal(image.content[0].type, 'image');
    assert.equal(
      Buffer.from(image.content[0].data, 'base64').length,
      Number(process.env.TEST_MCP_IMAGE_BYTES),
    );
    const stagedImage = await call('upload_theme_image', {
      data: image.content[0].data,
      name: 'AI theme image.png',
    });
    const pending = data(stagedImage);
    const preview = stagedImage.content.find((entry) => entry.type === 'image');
    assert.equal(preview?.data, image.content[0].data);
    const png = Buffer.from(preview.data, 'base64');
    const ownedImage = data(
      await call('verify_theme_image', {
        ...pending,
        width: png.readUInt32BE(16),
        height: png.readUInt32BE(20),
      }),
    );
    assert.ok(ownedImage.url.startsWith(`/theme-assets/${environment.HXPRESS_THEME_ID}/`));
    const ownedLibrary = data(await call('search_theme_assets'));
    assert.ok(ownedLibrary.images.some((item) => item.id === ownedImage.id));
    const ownedRead = await call('read_theme_asset_image', { id: ownedImage.id });
    assert.ok(!ownedRead.isError);
    assert.equal(ownedRead.content[0].data, image.content[0].data);
    const inserted = data(
      await call('edit_design', {
        expectedVersion: saved.version,
        operations: [{ action: 'insert', target: { scope: 'Home', section }, preset: 'image' }],
      }),
    );
    const block = inserted.created[0].block;
    const attached = data(
      await call('set_theme_block_image', {
        expectedVersion: inserted.version,
        target: { scope: 'Home', section, block },
        imageUrl: ownedImage.url,
        alt: 'Uploaded through MCP',
      }),
    );
    const inspected = data(await call('get_theme_section', { scope: 'Home', sectionId: section }));
    assert.ok(
      inspected.section.blocks.some((node) => node.id === block && node.image === ownedImage.url),
    );
    assert.equal(inspected.version, attached.version);
    latestVersion =
      mode === 'legacy' ? await verifyPresets(call, data, attached.version) : attached.version;
  } catch (error) {
    throw new Error(`Streamable HTTP / ${JSON.stringify(mode)}: ${error.message}`);
  } finally {
    await client.close();
  }
}
process.stdout.write(
  `${JSON.stringify({
    modern: true,
    legacy: true,
    hosted: true,
    version: latestVersion,
    imageRead: true,
  })}\n`,
);
