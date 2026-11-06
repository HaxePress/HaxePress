import type { McpServer } from '@modelcontextprotocol/server';
import * as z from 'zod/v4';
import { addTool, adminResult, type AdminRequest } from './admin-bridge';

const kind = z
  .string()
  .regex(/^[a-z][a-z0-9_]{0,31}$/)
  .describe(
    'Collection key, such as entry for articles, page for pages, or a custom collection key.',
  );
const id = z.number().int().min(1).max(2147483647);
const slug = z
  .string()
  .max(180)
  .regex(/^[a-z0-9]+(?:-[a-z0-9]+)*$/);
const status = z.enum(['draft', 'published', 'scheduled']);
const documentKey = z.object({ collection: kind, id });
const currentDocument = documentKey.extend({ expectedVersion: id });
const contentFields = z
  .object({
    title: z.string().min(1).max(180),
    slug,
    excerpt: z.string().max(500),
    body: z.string().max(100000),
    category: z.string().max(80),
    tagIds: z.array(id).max(100),
    featured: z.boolean(),
    status,
    publishDate: z.string().max(50),
    scheduledEpoch: z.number().min(0),
    seoTitle: z.string().max(180),
    seoDescription: z.string().max(500),
    customFields: z.record(z.string(), z.unknown()),
  })
  .partial();

type ContentFields = z.output<typeof contentFields>;
type CurrentDocument = z.output<typeof currentDocument>;

interface Editor {
  item: {
    title: string;
    slug: string;
    excerpt: string;
    content: string;
    category: string;
    image: string;
    image_alt: string;
    version: number;
    featured: number | boolean;
    status: string;
    published_at: string;
    scheduled_epoch: number;
    seo_title: string;
    seo_description: string;
    tags: { id: number }[];
    fields: Record<string, unknown>;
  };
  workingCopy?: unknown;
  contentType: { features: string[] };
}

function collectionPath(collection: string) {
  return `/admin/collections/${collection}`;
}

function saveFields(changes: ContentFields, item?: Editor['item']) {
  return {
    title: changes.title ?? item?.title ?? '',
    slug: changes.slug ?? item?.slug ?? '',
    excerpt: changes.excerpt ?? item?.excerpt ?? '',
    content: changes.body ?? item?.content ?? '',
    category: changes.category ?? item?.category ?? '',
    image: item?.image ?? '',
    image_alt: item?.image_alt ?? '',
    status: changes.status ?? item?.status ?? 'draft',
    featured: (changes.featured ?? Boolean(item?.featured)) ? '1' : '0',
    published_at: changes.publishDate ?? item?.published_at?.slice(0, 10) ?? '',
    scheduled_epoch: String(changes.scheduledEpoch ?? item?.scheduled_epoch ?? 0),
    tags: (changes.tagIds ?? item?.tags?.map((tag) => tag.id) ?? []).join(','),
    seo_title: changes.seoTitle ?? item?.seo_title ?? '',
    seo_description: changes.seoDescription ?? item?.seo_description ?? '',
    custom_fields: JSON.stringify(changes.customFields ?? item?.fields ?? {}),
  };
}

export function registerContentTools(
  server: McpServer,
  request: AdminRequest,
  canMedia: boolean,
  canPublish: boolean,
) {
  async function editor({ collection, id, expectedVersion }: CurrentDocument): Promise<Editor> {
    const response = await request(`${collectionPath(collection)}/${id}/edit`);
    const page = response.data as { component?: string; props?: Editor } | undefined;
    if (page?.component !== 'Admin/Editor' || !page.props)
      throw new Error('The content editor is unavailable.');
    if (page.props.item.version !== expectedVersion)
      throw new Error(
        `The content changed. Read version ${page.props.item.version} before editing.`,
      );
    if (page.props.workingCopy)
      throw new Error(
        'Save or discard the open working copy in the editor before changing this item.',
      );
    return page.props;
  }

  async function save(document: CurrentDocument, fields: Record<string, unknown>) {
    return adminResult(
      await request(`${collectionPath(document.collection)}/save`, 'POST', {
        ...fields,
        id: String(document.id),
        version: String(document.expectedVersion),
        stay: '1',
      }),
    );
  }

  addTool(
    server,
    'list_content',
    'Find content in a collection with bounded search, status and cursor filters.',
    z.object({
      collection: kind,
      query: z.string().max(120).optional(),
      status: z.enum(['draft', 'published', 'scheduled', 'trash']).optional(),
      cursor: z.string().max(1000).optional(),
    }),
    true,
    async ({ collection, query, status, cursor }) => {
      const params = new URLSearchParams();
      if (query) params.set('q', query);
      if (status) params.set('status', status);
      if (cursor) params.set('cursor', cursor);
      return adminResult(await request(`${collectionPath(collection)}?${params}`));
    },
  );
  addTool(
    server,
    'get_content',
    'Read one item, including its body, managed media and current version.',
    documentKey,
    true,
    async ({ collection, id }) =>
      adminResult(await request(`${collectionPath(collection)}/${id}/edit`)),
  );
  addTool(
    server,
    'create_content',
    'Create content in a collection. Draft is the default status.',
    z.object({ collection: kind, fields: contentFields.required({ title: true, slug: true }) }),
    false,
    async ({ collection, fields }) =>
      adminResult(await request(`${collectionPath(collection)}/save`, 'POST', saveFields(fields))),
  );
  addTool(
    server,
    'update_content',
    'Update selected fields on the saved item using its current version.',
    currentDocument.extend({ fields: contentFields }),
    false,
    async ({ fields, ...document }) => {
      const { item } = await editor(document);
      return save(document, saveFields(fields, item));
    },
  );

  if (canPublish) {
    addTool(
      server,
      'publish_content',
      'Publish the saved version of an item.',
      currentDocument,
      false,
      async (document) => {
        const { item } = await editor(document);
        return save(document, saveFields({ status: 'published' }, item));
      },
    );
  }

  // Only people can delete content permanently; the CMS refuses it for MCP clients.
  for (const [tool, operation, description] of [
    [
      'trash_content',
      'trash',
      'Move a content item to the trash. A person can restore it or delete it permanently.',
    ],
    ['restore_content', 'restore', 'Restore a trashed content item.'],
  ] as const) {
    addTool(server, tool, description, documentKey, false, async ({ collection, id }) =>
      adminResult(await request(`${collectionPath(collection)}/${id}/${operation}`, 'POST')),
    );
  }
  addTool(
    server,
    'list_content_revisions',
    'Read the revision history for one content item.',
    documentKey,
    true,
    async ({ collection, id }) =>
      adminResult(await request(`${collectionPath(collection)}/${id}/history`)),
  );
  const revision = documentKey.extend({ revision: id });
  addTool(
    server,
    'get_content_revision',
    'Read one historical version of a content item.',
    revision,
    true,
    async ({ collection, id, revision }) =>
      adminResult(await request(`${collectionPath(collection)}/${id}/history/${revision}`)),
  );
  addTool(
    server,
    'restore_content_revision',
    'Restore a historical version through the CMS history workflow.',
    revision,
    false,
    async ({ collection, id, revision }) =>
      adminResult(
        await request(`${collectionPath(collection)}/${id}/history/${revision}/restore`, 'POST'),
      ),
  );

  if (canMedia) {
    const attachment = currentDocument.extend({ mediaId: id, alt: z.string().max(500).optional() });
    async function media(mediaId: number) {
      const { data } = await request(`/admin/ai/media/${mediaId}/info`);
      const image = data as { url: string; alt: string };
      if (!image?.url) throw new Error('Choose a verified media library image.');
      return image;
    }
    addTool(
      server,
      'set_content_cover',
      'Set the cover from a verified media ID. Use upload_media_image and verify_media_image before attaching a new upload.',
      attachment,
      false,
      async ({ mediaId, alt, ...document }) => {
        const { item, contentType } = await editor(document);
        if (!contentType.features.includes('image'))
          throw new Error('This collection does not have a cover image field.');
        const image = await media(mediaId);
        return save(document, {
          ...saveFields({}, item),
          image: image.url,
          image_alt: alt ?? image.alt,
        });
      },
    );
    addTool(
      server,
      'insert_content_image',
      'Insert a verified media image at the start or end of an article’s Markdown body.',
      attachment.extend({ position: z.enum(['start', 'end']).optional() }),
      false,
      async ({ mediaId, alt, position, ...document }) => {
        const { item, contentType } = await editor(document);
        if (!contentType.features.includes('body'))
          throw new Error('This collection does not have a Markdown body.');
        const image = await media(mediaId);
        const text = (alt ?? image.alt).replace(/[\r\n]/g, ' ').replace(/[\\\[\]]/g, '\\$&');
        const markdown = `![${text}](${image.url})`;
        const body =
          position === 'start'
            ? `${markdown}\n\n${item.content}`
            : `${item.content}\n\n${markdown}`;
        return save(document, saveFields({ body }, item));
      },
    );
  }
}
