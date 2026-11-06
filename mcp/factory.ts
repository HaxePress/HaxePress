import { McpServer, type CallToolResult, type ToolAnnotations } from '@modelcontextprotocol/server';
import { createHash } from 'node:crypto';
import * as z from 'zod/v4';
import { applyOperations, type Operation } from './operations';
import {
  blockLabels,
  htmlTags,
  MAX_BYTES,
  MAX_DEPTH,
  MAX_NODES,
  sectionsFor,
  scopesFor,
  templateNames,
  type ThemeDocument,
} from '../resources/js/themes/builder/types';
import { layoutPresets } from '../resources/js/themes/builder/presets';
import { sectionChoices } from '../resources/js/themes/builder/friendly-presets';
import {
  attachedFile,
  encodedImage,
  fileInputMetadata,
  imageInput,
  MAX_IMAGE_BYTES,
  readBody,
} from './media-input';

declare const __CMS_VERSION__: string;
export interface ThemeServerOptions {
  themeId?: string;
  token?: string;
  ticket?: string;
  origin: string;
  signal?: AbortSignal;
  permissions: { read: boolean; edit: boolean; media: boolean };
}

export function createThemeServer(options: ThemeServerOptions) {
  const server = new McpServer({ name: 'haxepress-theme-editor', version: __CMS_VERSION__ });
  registerThemeTools(server, options);
  return server;
}

const themeIdentifier = z
  .string()
  .max(80)
  .regex(/^theme-[a-z0-9]+(?:-[a-z0-9]+)*$/);
const adminNames: Record<string, string> = {
  get_design_guide: 'get_theme_design_guide',
  get_design: 'get_theme_design',
  edit_design: 'edit_theme_design',
  replace_design: 'replace_theme_design',
  search_media: 'search_media_for_theme',
  get_collection_schema: 'get_theme_collection_schema',
  read_media_image: 'read_media_for_theme',
  search_theme_assets: 'search_theme_assets',
  read_theme_asset_image: 'read_theme_asset_image',
  upload_theme_image: 'upload_theme_image',
  verify_theme_image: 'verify_theme_image',
};

export function registerThemeTools(server: McpServer, options: ThemeServerOptions) {
  const { themeId, token, ticket } = options;
  const address = new URL(options.origin);
  if (
    address.origin !== options.origin ||
    address.protocol !== 'http:' ||
    address.hostname !== '127.0.0.1'
  ) {
    throw new Error('The theme bridge requires the site loopback origin.');
  }
  const credentials: Record<string, string> = ticket
    ? { 'X-HaxePress-Admin-Request': ticket }
    : { Authorization: `Bearer ${token}` };
  const themeEndpoint = (id: string) =>
    `${address.origin}/api/theme-designer/${encodeURIComponent(id)}`;
  if (themeId) themeIdentifier.parse(themeId);

  function register<Shape extends z.ZodRawShape>(
    name: string,
    config: {
      description: string;
      inputSchema: z.ZodObject<Shape>;
      annotations: ToolAnnotations;
      _meta?: Record<string, unknown>;
    },
    execute: (
      args: z.output<z.ZodObject<Shape>>,
      endpoint: string,
    ) => CallToolResult | Promise<CallToolResult>,
  ) {
    if (themeId || name === 'get_design_guide') {
      server.registerTool(themeId ? name : adminNames[name], config, (args) =>
        execute(args as z.output<z.ZodObject<Shape>>, themeId ? themeEndpoint(themeId) : ''),
      );
      return;
    }
    const schema = config.inputSchema.extend({ themeId: themeIdentifier });
    server.registerTool(adminNames[name] || name, { ...config, inputSchema: schema }, (args) => {
      const { themeId, ...fields } = args as { themeId: string } & Record<string, unknown>;
      return execute(fields as z.output<z.ZodObject<Shape>>, themeEndpoint(themeId));
    });
  }

  const selection = z.object({
    scope: z.string().min(1).max(81),
    section: z.string().max(40),
    block: z.string().max(40).optional(),
  });
  const version = z.number().int().min(1).max(999999999);
  const operations = z
    .array(
      z.object({
        action: z.enum([
          'insert',
          'section',
          'update',
          'style',
          'move',
          'remove',
          'duplicate',
          'tokens',
          'css',
        ]),
        target: selection.optional(),
        destination: selection
          .extend({ position: z.enum(['before', 'after', 'inside']).optional() })
          .optional(),
        preset: z.string().max(80).optional(),
        name: z.string().max(80).optional(),
        values: z.record(z.string(), z.unknown()).optional(),
        breakpoint: z.enum(['desktop', 'tablet', 'mobile']).optional(),
        state: z.enum(['normal', 'hover', 'focus']).optional(),
        text: z.string().max(64000).optional(),
      }),
    )
    .min(1)
    .max(100);

  async function api(endpoint: string, path: string, data?: unknown) {
    const response = await fetch(`${endpoint}${path}`, {
      method: data === undefined ? 'GET' : 'POST',
      redirect: 'error',
      signal: AbortSignal.any([
        AbortSignal.timeout(20000),
        ...(options.signal ? [options.signal] : []),
      ]),
      headers: {
        ...credentials,
        Accept: 'application/json',
        ...(data === undefined ? {} : { 'Content-Type': 'application/json' }),
      },
      body: data === undefined ? undefined : JSON.stringify(data),
    });
    const source = await response.text();
    if (Buffer.byteLength(source) > 2 * MAX_BYTES)
      throw new Error('The CMS response exceeded the design response limit.');
    if (!response.headers.get('content-type')?.includes('application/json'))
      throw new Error('The CMS did not return a design API response.');
    const result = JSON.parse(source);
    if (!response.ok) throw new Error(result.error || 'The CMS rejected this design request.');
    return result;
  }
  function result(value: Record<string, unknown>) {
    return {
      content: [{ type: 'text' as const, text: JSON.stringify(value) }],
      structuredContent: value,
    };
  }
  async function safely(action: () => Promise<Record<string, unknown>>) {
    try {
      return result(await action());
    } catch (error) {
      return {
        content: [
          {
            type: 'text' as const,
            text: error instanceof Error ? error.message : 'The design request failed.',
          },
        ],
        isError: true,
      };
    }
  }
  function validateSize(document: unknown) {
    const source = JSON.stringify(document);
    if (Buffer.byteLength(source) > MAX_BYTES) throw new Error('The theme design exceeds 1 MB.');
    return source;
  }
  async function current(endpoint: string, expectedVersion?: number) {
    const data = await api(endpoint, '/design');
    if (expectedVersion !== undefined && data.theme.version !== expectedVersion)
      throw new Error(
        `The saved design changed. Read it again before editing. Current version: ${data.theme.version}`,
      );
    return data;
  }
  const guide = {
    schema: 2,
    coreTemplates: templateNames,
    blockTypes: Object.keys(blockLabels),
    htmlTags,
    layouts: layoutPresets,
    sections: sectionChoices.map(({ id, name }) => ({ id, name })),
    limits: {
      bytes: MAX_BYTES,
      nodes: MAX_NODES,
      depth: MAX_DEPTH,
      operations: 100,
      mediaPerDesign: 128,
      feedLimit: 24,
    },
    workflow:
      'Read get_design and its version first. Use edit_design for small atomic changes, or replace_design for an entirely new theme. Design edits need expectedVersion and save a draft. The user reviews and publishes in the editor.',
    layout:
      'Sections own blocks. Containers, semantic elements and repeaters may own children. Core templates must remain present. Reusable components live in document.components and render with a component block. Add custom layouts in document.templates plus templateMeta with a label and core-template fallback.',
    content:
      'Use text, image and href for authored content. Use bindings.text=item.title, bindings.image=item.image, bindings.href=item.url for dynamic content. A repeat block uses page.items, page.related or feed:<id>. Feeds are bounded collection queries with collection, limit, category, tag, query, order and direction. Plugin areas use extension blocks with slot names.',
    styles:
      'styles.desktop.normal is the base CSS map. styles.tablet and styles.mobile override it; hover and focus are independent states. CSS values are strings. Global tokens hold background, text, accent, font, width and radius. Shared appearances live in classes; css holds scoped theme CSS. Set an empty style value to inherit.',
    images:
      'Stage theme images with upload_theme_image, check the returned image, then call verify_theme_image with its ID, hash and dimensions. Use search_theme_assets or search_media to find existing images. Images and CSS backgrounds use the managed media library. Do not insert remote image URLs or executable HTML. Site branding and menu blocks use the CMS site settings and navigation.',
    identifiers:
      'Existing node IDs are stable. Insert and duplicate operations return fresh IDs. When replacing a document, use unique ASCII IDs up to 40 characters. Operations on nonexistent nodes or invalid nested moves fail without saving.',
  };

  const readOnly = { readOnlyHint: true, destructiveHint: false, openWorldHint: false };
  const edit = { readOnlyHint: false, destructiveHint: true, openWorldHint: false };
  if (options.permissions.read) {
    register(
      'get_design_guide',
      {
        description:
          'Read the HaxePress theme schema, layout primitives, bindings, native constraints and safe editing workflow.',
        inputSchema: z.object({}),
        annotations: readOnly,
      },
      async () => result(guide),
    );
    server.registerResource(
      'design-guide',
      'haxepress://theme/design-guide',
      { mimeType: 'application/json', description: 'The editable theme design contract.' },
      async () => ({
        contents: [
          {
            uri: 'haxepress://theme/design-guide',
            mimeType: 'application/json',
            text: JSON.stringify(guide),
          },
        ],
      }),
    );
    register(
      'get_design',
      {
        description:
          'Read the current saved draft, version and available content collections. Optionally return only the sections in a named scope.',
        inputSchema: z.object({ scope: z.string().max(81).optional() }),
        annotations: readOnly,
      },
      async ({ scope }, endpoint) =>
        safely(async () => {
          const data = await current(endpoint);
          if (!scope) return data;
          if (!scopesFor(data.theme.document).includes(scope))
            throw new Error('Choose an existing template, header, footer or @component scope.');
          return {
            name: data.theme.name,
            version: data.theme.version,
            publishedVersion: data.theme.publishedVersion,
            scope,
            sections: sectionsFor(data.theme.document, scope),
            tokens: data.theme.document.tokens,
            collections: data.collections,
          };
        }),
    );
  }
  if (options.permissions.edit) {
    register(
      'edit_design',
      {
        description:
          'Apply up to 100 atomic edits to this theme draft using the shared visual-editor operations. It never publishes or activates a theme.',
        inputSchema: z.object({ expectedVersion: version, operations }),
        annotations: edit,
      },
      async ({ expectedVersion, operations }, endpoint) =>
        safely(async () => {
          const data = await current(endpoint, expectedVersion);
          const document: ThemeDocument = structuredClone(data.theme.document);
          const created = applyOperations(document, operations as Operation[]);
          const saved = await api(endpoint, '/design', {
            name: data.theme.name,
            version: String(expectedVersion),
            design: validateSize(document),
          });
          return { ...saved, created };
        }),
    );
    register(
      'replace_design',
      {
        description:
          'Replace the entire saved theme draft with a schema-2 document after native CMS validation. Keep all core templates. Use this for a complete new design or changes to reusable components, custom templates, classes or feeds.',
        inputSchema: z.object({
          expectedVersion: version,
          name: z.string().min(2).max(100).optional(),
          document: z.record(z.string(), z.unknown()),
        }),
        annotations: edit,
      },
      async ({ expectedVersion, name, document }, endpoint) =>
        safely(async () => {
          const data = await current(endpoint, expectedVersion);
          return api(endpoint, '/design', {
            name: name || data.theme.name,
            version: String(expectedVersion),
            design: validateSize(document),
          });
        }),
    );
  }
  if (options.permissions.media) {
    register(
      'search_media',
      {
        description:
          'Find managed images in the permitted media library. Results use bounded cursor pagination and contain URLs, descriptions and dimensions.',
        inputSchema: z.object({
          query: z.string().max(80).optional(),
          cursor: z.string().max(1000).optional(),
        }),
        annotations: readOnly,
      },
      async ({ query, cursor }, endpoint) =>
        safely(async () => {
          const parameters = new URLSearchParams();
          if (query) parameters.set('q', query);
          if (cursor) parameters.set('cursor', cursor);
          const response = await api(endpoint, `/media?${parameters}`);
          const nextCursor = response.pagination.next
            ? new URL(response.pagination.next, address.origin).searchParams.get('cursor')
            : null;
          const previousCursor = response.pagination.previous
            ? new URL(response.pagination.previous, address.origin).searchParams.get('cursor')
            : null;
          return { ...response, nextCursor, previousCursor };
        }),
    );
  }
  if (options.permissions.read) {
    register(
      'get_collection_schema',
      {
        description:
          'Read the public custom fields and display features of a specific content collection before binding them into a theme. It returns schema metadata, not content records.',
        inputSchema: z.object({ key: z.string().regex(/^[a-z][a-z0-9_]{0,31}$/) }),
        annotations: readOnly,
      },
      async ({ key }, endpoint) =>
        safely(() => api(endpoint, `/collections/${encodeURIComponent(key)}`)),
    );
  }
  if (options.permissions.media) {
    register(
      'read_media_image',
      {
        description:
          'View one permitted library image before choosing it for a design. Accepts a media ID from search_media and returns image content, up to the native 5 MB limit.',
        inputSchema: z.object({ id: z.number().int().positive().max(2147483647) }),
        annotations: readOnly,
      },
      async ({ id }, endpoint) => {
        try {
          const response = await fetch(`${endpoint}/media/${id}`, {
            headers: credentials,
            redirect: 'error',
            signal: AbortSignal.any([
              AbortSignal.timeout(20000),
              ...(options.signal ? [options.signal] : []),
            ]),
          });
          if (!response.ok)
            throw new Error(
              'The image is unavailable or this account cannot access the media library.',
            );
          const mimeType = response.headers.get('content-type')?.split(';')[0] || '';
          if (
            !['image/jpeg', 'image/png', 'image/webp', 'image/gif'].includes(mimeType) ||
            Number(response.headers.get('content-length')) > 5 * 1024 * 1024
          )
            throw new Error('Choose a supported image under 5 MB.');
          const bytes = await readBody(response, MAX_IMAGE_BYTES);
          if (bytes.length > 5 * 1024 * 1024) throw new Error('Choose an image under 5 MB.');
          return {
            content: [{ type: 'image' as const, mimeType, data: bytes.toString('base64') }],
          };
        } catch (error) {
          return {
            content: [
              {
                type: 'text' as const,
                text: error instanceof Error ? error.message : 'The image could not be read.',
              },
            ],
            isError: true,
          };
        }
      },
    );
  }
  if (options.permissions.read) {
    register(
      'search_theme_assets',
      {
        description:
          'Find images owned by this theme. They live in theme storage, are included in theme exports, and do not require access to the site media library.',
        inputSchema: z.object({
          query: z.string().max(80).optional(),
          cursor: z.string().max(1000).optional(),
        }),
        annotations: readOnly,
      },
      async ({ query, cursor }, endpoint) =>
        safely(async () => {
          const parameters = new URLSearchParams();
          if (query) parameters.set('q', query);
          if (cursor) parameters.set('cursor', cursor);
          const response = await api(endpoint, `/assets?${parameters}`);
          return {
            ...response,
            nextCursor: response.pagination.next
              ? new URL(response.pagination.next, address.origin).searchParams.get('cursor')
              : null,
          };
        }),
    );
    register(
      'read_theme_asset_image',
      {
        description:
          'View an image owned by this theme, using an ID returned by search_theme_assets. It reads the theme image store, not the site media library.',
        inputSchema: z.object({ id: z.number().int().positive().max(2147483647) }),
        annotations: readOnly,
      },
      async ({ id }, endpoint) => {
        try {
          const response = await fetch(`${endpoint}/assets/${id}`, {
            headers: credentials,
            redirect: 'error',
            signal: AbortSignal.any([
              AbortSignal.timeout(20000),
              ...(options.signal ? [options.signal] : []),
            ]),
          });
          if (!response.ok) throw new Error('Choose an available image owned by this theme.');
          const bytes = await readBody(response, MAX_IMAGE_BYTES);
          if (bytes.length > 5 * 1024 * 1024) throw new Error('Choose an image under 5 MB.');
          const mimeType = response.headers.get('content-type')?.split(';')[0] || '';
          if (!['image/png', 'image/jpeg', 'image/webp', 'image/gif'].includes(mimeType))
            throw new Error('Choose a supported theme image.');
          return {
            content: [{ type: 'image' as const, mimeType, data: bytes.toString('base64') }],
          };
        } catch (error) {
          return {
            content: [
              {
                type: 'text' as const,
                text: error instanceof Error ? error.message : 'The theme image could not be read.',
              },
            ],
            isError: true,
          };
        }
      },
    );
  }
  if (options.permissions.edit) {
    register(
      'upload_theme_image',
      {
        description:
          'Stage a JPEG, PNG or GIF attachment or canonical Base64 image, up to 5 MB. The response includes the uploaded image, its ID and SHA-256 hash. Check the image and call verify_theme_image to save it to this theme.',
        inputSchema: z.object({
          data: encodedImage.optional(),
          file: attachedFile.optional(),
          name: z.string().max(180).optional(),
        }),
        annotations: edit,
        _meta: fileInputMetadata,
      },
      async ({ data, file, name }, endpoint) => {
        try {
          const { bytes, name: filename } = await imageInput(data, file, name, options.signal);
          const response = await fetch(`${endpoint}/assets`, {
            method: 'POST',
            redirect: 'error',
            body: bytes,
            headers: {
              ...credentials,
              Accept: 'image/*, application/json',
              'Content-Type': 'application/octet-stream',
              'X-File-Name': encodeURIComponent(filename || 'Theme image'),
            },
            signal: AbortSignal.any([
              AbortSignal.timeout(20000),
              ...(options.signal ? [options.signal] : []),
            ]),
          });
          if (response.status !== 202) {
            const error = response.headers.get('content-type')?.includes('application/json')
              ? (await response.json()).error
              : null;
            throw new Error(error || 'The theme image could not be uploaded.');
          }
          const id = response.headers.get('x-upload-id');
          const mimeType = response.headers.get('content-type')?.split(';')[0] || '';
          const uploaded = await readBody(response, MAX_IMAGE_BYTES);
          const sha256 = createHash('sha256').update(uploaded).digest('hex');
          const originalHash = createHash('sha256').update(bytes).digest('hex');
          if (
            !id ||
            sha256 !== originalHash ||
            !['image/jpeg', 'image/png', 'image/gif'].includes(mimeType)
          ) {
            throw new Error('The uploaded image does not match the selected file.');
          }
          const pending = result({ id, sha256 });
          return {
            ...pending,
            content: [
              ...pending.content,
              { type: 'image' as const, mimeType, data: uploaded.toString('base64') },
            ],
          };
        } catch (error) {
          return {
            content: [
              {
                type: 'text' as const,
                text:
                  error instanceof Error ? error.message : 'The theme image could not be uploaded.',
              },
            ],
            isError: true,
          };
        }
      },
    );
    register(
      'verify_theme_image',
      {
        description:
          'Confirm a staged theme image after checking that it displays and matches the original file. Supply the upload ID, SHA-256 hash and measured pixel dimensions. The result includes its saved theme image URL.',
        inputSchema: z.object({
          id: z.string().regex(/^[A-Za-z0-9_-]{32}$/),
          sha256: z.string().regex(/^[a-f0-9]{64}$/),
          width: z.number().int().min(1).max(10000),
          height: z.number().int().min(1).max(10000),
        }),
        annotations: edit,
      },
      async (confirmation, endpoint) => safely(() => api(endpoint, '/assets/verify', confirmation)),
    );
  }

  if (!themeId && options.permissions.read) {
    register(
      'inspect_theme_tree',
      {
        description:
          'List template, shared layout and component scopes with their section and block IDs. Use the IDs for targeted design changes.',
        inputSchema: z.object({ scope: z.string().max(81).optional() }),
        annotations: readOnly,
      },
      ({ scope }, endpoint) =>
        safely(async () => {
          const { theme } = await current(endpoint);
          const available = scopesFor(theme.document);
          if (scope && !available.includes(scope))
            throw new Error('Choose an existing theme scope.');
          const summarize = (blocks: ThemeDocument['header'][number]['blocks']): unknown[] =>
            blocks.map((block) => ({
              id: block.id,
              type: block.type,
              children: summarize(block.children || []),
            }));
          const scopes = scope ? [scope] : available;
          return {
            version: theme.version,
            scopes: scopes.map((name) => ({
              name,
              sections: sectionsFor(theme.document, name).map((section) => ({
                id: section.id,
                name: section.name,
                blocks: summarize(section.blocks),
              })),
            })),
          };
        }),
    );
    register(
      'get_theme_section',
      {
        description:
          'Read one theme section with its nested blocks, bindings, responsive styles and IDs.',
        inputSchema: z.object({ scope: z.string().max(81), sectionId: z.string().max(40) }),
        annotations: readOnly,
      },
      ({ scope, sectionId }, endpoint) =>
        safely(async () => {
          const { theme } = await current(endpoint);
          const section = sectionsFor(theme.document, scope).find((item) => item.id === sectionId);
          if (!section) throw new Error('Choose an existing section from inspect_theme_tree.');
          return { version: theme.version, scope, section };
        }),
    );
  }
  if (!themeId && options.permissions.edit) {
    register(
      'set_theme_block_image',
      {
        description:
          'Set a block’s image using the managed URL returned by verify_theme_image or search_theme_assets. Saves the theme draft.',
        inputSchema: z.object({
          expectedVersion: version,
          target: selection.extend({ block: z.string().min(1).max(40) }),
          imageUrl: z.string().max(500),
          alt: z.string().max(500).optional(),
        }),
        annotations: edit,
      },
      ({ expectedVersion, target, imageUrl, alt }, endpoint) =>
        safely(async () => {
          const { theme } = await current(endpoint, expectedVersion);
          const document: ThemeDocument = structuredClone(theme.document);
          const values = { image: imageUrl, ...(alt === undefined ? {} : { alt }) };
          applyOperations(document, [{ action: 'update', target, values }]);
          return api(endpoint, '/design', {
            name: theme.name,
            version: String(expectedVersion),
            design: validateSize(document),
          });
        }),
    );
  }
}
