import { createHash } from 'node:crypto';
import { McpServer } from '@modelcontextprotocol/server';
import * as z from 'zod/v4';
import { registerContentTools } from './content-tools';
import { skillPointer } from './skills';
import {
  addTool,
  adminBridge,
  adminResult,
  jsonResult,
  type AdminServerOptions,
} from './admin-bridge';
import { registerThemeTools } from './factory';
import { attachedFile, encodedImage, fileInputMetadata, imageInput } from './media-input';

declare const __CMS_VERSION__: string;

interface PluginTool {
  name: string;
  description: string;
  path: string;
  method: 'GET' | 'POST' | 'DELETE';
  inputSchema: Record<string, unknown>;
}

interface Catalog {
  navigation: unknown;
  routes: { path: string; methods: string[] }[];
  capabilities: string[];
  tools: PluginTool[];
}

const id = z.number().int().min(1).max(2147483647);
const key = z.string().regex(/^[a-z][a-z0-9_-]{0,79}$/);
const fields = z.record(z.string(), z.unknown());
const page = z.object({
  q: z.string().max(80).optional(),
  cursor: z.string().max(1000).optional(),
});

function browsePath(path: string, args: { q?: string; cursor?: string }) {
  const params = new URLSearchParams();
  if (args.q) params.set('q', args.q);
  if (args.cursor) params.set('cursor', args.cursor);
  return params.size ? `${path}?${params}` : path;
}

export async function createAdminServer(options: AdminServerOptions) {
  const request = adminBridge(options);
  const { data } = await request('/admin/ai/routes');
  const catalog = data as Catalog;
  const can = (capability: string) =>
    catalog.capabilities.includes('*') || catalog.capabilities.includes(capability);
  const server = new McpServer(
    { name: 'haxepress-admin', version: __CMS_VERSION__ },
    {
      instructions: [
        'Use the named CMS tools. Read the saved version before editing content or a theme.',
        'For articles, upload_media_image stages original bytes or an attachment. Inspect the returned image and confirm its hash and dimensions with verify_media_image, then use set_content_cover or insert_content_image.',
        'For themes, start with list_themes and inspect_theme_tree. Use upload_theme_image, verify_theme_image and set_theme_block_image for theme-owned images.',
        ...(can('extensions') ? [skillPointer] : []),
      ].join(' '),
    },
  );
  const empty = z.object({});
  const name = z.string().trim().min(1).max(100);
  const genericPath = z.string().startsWith('/admin').max(1024);

  addTool(
    server,
    'get_admin_routes',
    'Discover the current administrator’s navigation and CMS route templates.',
    empty,
    true,
    () => jsonResult({ data: { navigation: catalog.navigation, routes: catalog.routes } }),
  );
  addTool(
    server,
    'read_admin',
    'Read a native admin route when a specific tool is unavailable.',
    z.object({ path: genericPath }),
    true,
    async ({ path }) => adminResult(await request(path)),
  );
  addTool(
    server,
    'write_admin',
    'Run a native form action when a specific tool is unavailable. Use its declared input fields.',
    z.object({ path: genericPath, method: z.enum(['POST', 'DELETE']), data: fields.optional() }),
    false,
    async ({ path, method, data }) => adminResult(await request(path, method, data)),
  );

  const lists = [
    ['get_dashboard', '', '/admin', 'Read CMS counts, recent content and activity.'],
    [
      'list_collections',
      '',
      '/admin/collections',
      'List collections and their editor capabilities.',
    ],
    ['list_categories', 'taxonomy', '/admin/categories', 'Search content categories.'],
    ['list_tags', 'taxonomy', '/admin/tags', 'Search content tags.'],
    [
      'list_media',
      'media',
      '/admin/media',
      'Search uploaded media and obtain managed image IDs and URLs.',
    ],
    ['list_themes', 'extensions', '/admin/themes', 'Find installed themes and editable theme IDs.'],
    [
      'list_plugins',
      'extensions',
      '/admin/plugins',
      'Find installed plugins and their activation state.',
    ],
    ['list_navigation', 'navigation', '/admin/navigation', 'Read navigation regions and links.'],
    [
      'get_site_settings',
      'settings',
      '/admin/settings',
      'Read site branding, language and homepage configuration.',
    ],
    ['list_team', 'team', '/admin/team', 'Read the current team and assigned roles.'],
    ['list_roles', 'roles', '/admin/roles', 'Read roles and their capability grants.'],
    ['list_activity', 'activity', '/admin/activity', 'Read the admin activity history.'],
    ['get_account', '', '/admin/account', 'Read your account profile.'],
    [
      'list_backup_schedules',
      'backups',
      '/admin/backups',
      'Read backup schedule settings and recent run status.',
    ],
  ] as const;
  for (const [tool, capability, path, description] of lists) {
    if (!capability || can(capability)) {
      addTool(server, tool, description, page, true, async (args) =>
        adminResult(await request(browsePath(path, args))),
      );
    }
  }

  registerContentTools(server, request, can('media'), can('publish'));

  if (can('taxonomy')) {
    addTool(
      server,
      'save_category',
      'Create or rename a category.',
      z.object({ id: id.optional(), name }),
      false,
      async ({ id, name }) =>
        adminResult(
          await request('/admin/categories/save', 'POST', { id: id ? String(id) : '', name }),
        ),
    );
    addTool(
      server,
      'save_tag',
      'Create or edit a tag.',
      z.object({ id: id.optional(), name, slug: key, description: z.string().max(500).optional() }),
      false,
      async ({ id, ...data }) =>
        adminResult(
          await request('/admin/tags/save', 'POST', { ...data, id: id ? String(id) : '' }),
        ),
    );
    for (const resource of ['categories', 'tags'] as const) {
      const item = resource === 'categories' ? 'category' : 'tag';
      addTool(
        server,
        `delete_${item}`,
        `Delete a ${item} through its native CMS checks.`,
        z.object({ id }),
        false,
        async ({ id }) => adminResult(await request(`/admin/${resource}/${id}/delete`, 'POST')),
      );
    }
  }

  if (can('media')) {
    addTool(
      server,
      'upload_media_image',
      'Stage a JPEG, PNG or GIF attachment or original Base64 image bytes. View the echoed image, verify its SHA-256 and measure its dimensions before calling verify_media_image.',
      z.object({
        base64: encodedImage.optional(),
        file: attachedFile.optional(),
        name: z.string().max(180).optional(),
      }),
      false,
      async ({ base64, file, name }) => {
        const upload = await imageInput(base64, file, name, options.signal);
        const response = await request('/admin/media/upload', 'POST', undefined, upload);
        const checksum = createHash('sha256').update(upload.bytes).digest('hex');
        if (
          response.status !== 202 ||
          !response.image?.uploadId ||
          response.image.sha256 !== checksum
        )
          throw new Error('The echoed upload does not match the original image.');
        return adminResult(response);
      },
      fileInputMetadata,
    );
    addTool(
      server,
      'verify_media_image',
      'Save a staged media image after inspecting the echoed bytes. Supply the upload ID, SHA-256 and measured width and height. The result contains the managed image ID and URL.',
      z.object({
        id: z.string().regex(/^[A-Za-z0-9_-]{32}$/),
        sha256: z.string().regex(/^[a-f0-9]{64}$/),
        width: z.number().int().min(1).max(10000),
        height: z.number().int().min(1).max(10000),
      }),
      false,
      async (data) => adminResult(await request('/admin/media/upload/verify', 'POST', data)),
    );
    addTool(
      server,
      'read_media_image',
      'View a verified media library image by ID.',
      z.object({ id }),
      true,
      async ({ id }) => adminResult(await request(`/admin/ai/media/${id}`)),
    );
    addTool(
      server,
      'get_media_references',
      'Read the content, settings and plugin references to an image.',
      z.object({ id }),
      true,
      async ({ id }) => adminResult(await request(`/admin/media/${id}/references`)),
    );
    addTool(
      server,
      'update_media_details',
      'Save the title and alternative text of an uploaded image.',
      z.object({ id, title: z.string().max(180), alt: z.string().max(500) }),
      false,
      async ({ id, ...data }) =>
        adminResult(await request(`/admin/media/${id}/save`, 'POST', data)),
    );
    addTool(
      server,
      'trash_media_image',
      'Move an uploaded image to the trash if the CMS finds no active references. Its public URL stops working; a person can restore it, and the trash deletes it after 30 days.',
      z.object({ id }),
      false,
      async ({ id }) => adminResult(await request(`/admin/media/${id}/trash`, 'POST')),
    );
    addTool(
      server,
      'restore_media_image',
      'Restore an image from the trash.',
      z.object({ id }),
      false,
      async ({ id }) => adminResult(await request(`/admin/media/${id}/restore`, 'POST')),
    );
  }

  if (can('navigation')) {
    addTool(
      server,
      'list_navigation_regions',
      'Read the available navigation regions.',
      empty,
      true,
      async () => adminResult(await request('/admin/navigation/regions')),
    );
    addTool(
      server,
      'save_navigation_link',
      'Create or edit a navigation link to a path, published item or collection.',
      z.object({
        id: id.optional(),
        label: z.string().max(80),
        location: key,
        position: z.number().int().min(0).max(9999),
        url: z.string().max(1000).optional(),
        contentId: id.optional(),
        collectionKey: key.optional(),
      }),
      false,
      async ({ id, label, location, position, url, contentId, collectionKey }) =>
        adminResult(
          await request('/admin/navigation/save', 'POST', {
            id: id ? String(id) : '',
            label,
            location,
            position: String(position),
            url: url || '',
            content_id: contentId ? String(contentId) : '',
            collection_key: collectionKey || '',
          }),
        ),
    );
    addTool(
      server,
      'delete_navigation_link',
      'Remove a navigation link by its ID.',
      z.object({ id }),
      false,
      async ({ id }) => adminResult(await request(`/admin/navigation/${id}/delete`, 'POST')),
    );
  }

  if (can('extensions')) {
    const extensionId = z
      .string()
      .max(100)
      .regex(/^(?:plugin|theme)-[a-z0-9]+(?:-[a-z0-9]+)*$/);
    const extension = z.object({ id: extensionId });
    addTool(
      server,
      'get_extension_settings',
      'Read editable settings for a theme or plugin.',
      extension,
      true,
      async ({ id }) =>
        adminResult(
          await request(`/admin/${id.startsWith('theme-') ? 'themes' : 'plugins'}/${id}/settings`),
        ),
    );
    for (const action of ['enable', 'disable'] as const) {
      addTool(
        server,
        `${action === 'enable' ? 'activate' : 'deactivate'}_plugin`,
        `${action} an installed plugin through its native lifecycle.`,
        z.object({
          id: z
            .string()
            .max(100)
            .regex(/^plugin-[a-z0-9]+(?:-[a-z0-9]+)*$/),
        }),
        false,
        async ({ id }) => adminResult(await request(`/admin/plugins/${id}/${action}`, 'POST')),
      );
    }
    addTool(
      server,
      'create_theme_draft',
      'Create an editable theme draft from a built-in starter.',
      z.object({ name, starter: z.enum(['blank', 'content']).optional() }),
      false,
      async ({ name, starter }) =>
        adminResult(
          await request('/admin/themes/create', 'POST', { name, starter: starter || 'blank' }),
        ),
    );
    registerThemeTools(server, {
      origin: options.origin,
      ticket: options.ticket,
      signal: options.signal,
      permissions: { read: true, edit: true, media: can('media') },
    });
  }

  if (can('settings')) {
    addTool(
      server,
      'get_collection_definition',
      'Read the field schema and configuration for a content collection.',
      z.object({ key }),
      true,
      async ({ key }) => adminResult(await request(`/admin/content-types/${key}/edit`)),
    );
    addTool(
      server,
      'save_collection_definition',
      'Create or edit a collection using its native configuration fields.',
      z.object({ key: key.optional(), definition: fields }),
      false,
      async ({ key, definition }) =>
        adminResult(
          await request(
            key ? `/admin/content-types/${key}/save` : '/admin/content-types/create',
            'POST',
            definition,
          ),
        ),
    );
    addTool(
      server,
      'save_site_settings',
      'Save the complete site settings form after reading get_site_settings.',
      z.object({ settings: fields }),
      false,
      async ({ settings }) => adminResult(await request('/admin/settings', 'POST', settings)),
    );
  }

  addTool(
    server,
    'update_account_name',
    'Change the display name of your current admin account.',
    z.object({ name }),
    false,
    async ({ name }) => adminResult(await request('/admin/account', 'POST', { name })),
  );

  for (const tool of catalog.tools) {
    let schema: z.ZodObject;
    try {
      const parsed = z.fromJSONSchema(tool.inputSchema);
      if (!(parsed instanceof z.ZodObject)) continue;
      schema = parsed;
    } catch {
      continue;
    }
    addTool(server, tool.name, tool.description, schema, tool.method === 'GET', async (values) => {
      const data = values as Record<string, unknown>;
      if (tool.method === 'GET') {
        const params = new URLSearchParams();
        for (const [key, value] of Object.entries(data)) {
          if (value != null)
            params.set(key, typeof value === 'string' ? value : JSON.stringify(value));
        }
        return adminResult(await request(params.size ? `${tool.path}?${params}` : tool.path));
      }
      return adminResult(await request(tool.path, tool.method, data));
    });
  }
  return server;
}
