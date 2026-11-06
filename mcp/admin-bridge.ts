import { createHash, randomBytes } from 'node:crypto';
import type { CallToolResult, McpServer } from '@modelcontextprotocol/server';
import type * as z from 'zod/v4';
import { MAX_IMAGE_BYTES, readBody } from './media-input';

export interface AdminServerOptions {
  origin: string;
  ticket: string;
  signal: AbortSignal;
}

export interface AdminReply {
  status: number;
  redirect?: string;
  data?: unknown;
  image?: { mimeType: string; data: string; size: number; sha256: string; uploadId: string | null };
}

export type AdminRequest = (
  path: string,
  method?: 'GET' | 'POST' | 'DELETE',
  data?: Record<string, unknown>,
  image?: { bytes: Uint8Array<ArrayBuffer>; name?: string },
) => Promise<AdminReply>;

const imageTypes = ['image/png', 'image/jpeg', 'image/gif', 'image/webp'];

export function jsonResult(value: Record<string, unknown>): CallToolResult {
  return {
    content: [{ type: 'text', text: JSON.stringify(value) }],
    structuredContent: value,
  };
}

export function adminResult({ status, redirect, data, image }: AdminReply): CallToolResult {
  if (image) {
    const { mimeType, data: imageBytes, ...info } = image;
    return {
      content: [
        { type: 'text', text: JSON.stringify(info) },
        { type: 'image', mimeType, data: imageBytes },
      ],
      structuredContent: { status, ...info },
    };
  }
  return jsonResult({ status, redirect, data });
}

export function addTool<Shape extends z.ZodRawShape>(
  server: McpServer,
  name: string,
  description: string,
  inputSchema: z.ZodObject<Shape>,
  readOnly: boolean,
  run: (args: z.output<z.ZodObject<Shape>>) => CallToolResult | Promise<CallToolResult>,
  metadata?: Record<string, unknown>,
) {
  server.registerTool(
    name,
    {
      description,
      inputSchema,
      annotations: { readOnlyHint: readOnly, destructiveHint: !readOnly, openWorldHint: false },
      _meta: metadata,
    },
    async (args): Promise<CallToolResult> => {
      try {
        return await run(args as z.output<z.ZodObject<Shape>>);
      } catch (error) {
        return {
          content: [
            {
              type: 'text',
              text: error instanceof Error ? error.message : 'The CMS action failed.',
            },
          ],
          isError: true,
        };
      }
    },
  );
}

export function adminBridge(options: AdminServerOptions): AdminRequest {
  const origin = new URL(options.origin);
  return async (input, method = 'GET', data, image) => {
    const target = new URL(input, origin);
    if (
      !input.startsWith('/admin') ||
      target.origin !== origin.origin ||
      (target.pathname !== '/admin' && !target.pathname.startsWith('/admin/')) ||
      target.hash ||
      /[\\\x00-\x20]/.test(input) ||
      /^\/admin\/(login|logout|install)(?:\/|$)/.test(target.pathname)
    ) {
      throw new Error('Choose a relative route in the HaxePress administration panel.');
    }
    const headers = new Headers({
      Accept: 'application/json',
      'X-Well-Data': 'true',
      'X-CSRF-TOKEN': randomBytes(24).toString('base64url'),
      'X-HaxePress-Admin-Request': options.ticket,
    });
    if (method !== 'GET') {
      headers.set('Content-Type', image ? 'application/octet-stream' : 'application/json');
    }
    if (image?.name) headers.set('X-File-Name', encodeURIComponent(image.name));
    const response = await fetch(target, {
      method,
      headers,
      redirect: 'manual',
      signal: AbortSignal.any([options.signal, AbortSignal.timeout(20000)]),
      ...(method !== 'GET' && { body: image ? image.bytes : JSON.stringify(data || {}) }),
    });
    const type = response.headers.get('content-type')?.split(';')[0] || '';
    const status = response.status;
    const isImage = response.ok && imageTypes.includes(type);
    const bytes = await readBody(response, isImage ? MAX_IMAGE_BYTES : 4 * 1024 * 1024);
    if (isImage) {
      return {
        status,
        image: {
          mimeType: type,
          data: bytes.toString('base64'),
          size: bytes.length,
          uploadId: response.headers.get('x-upload-id'),
          sha256: createHash('sha256').update(bytes).digest('hex'),
        },
      };
    }
    const redirect = response.headers.get('location') || undefined;
    const parsed =
      type === 'application/json' && bytes.length ? JSON.parse(bytes.toString('utf8')) : undefined;
    if (!response.ok && (status < 300 || status >= 400)) {
      const error =
        parsed?.error || parsed?.props?.message || Object.values(parsed?.props?.errors || {})[0];
      throw new Error(
        typeof error === 'string' ? error : `The admin route returned HTTP ${status}.`,
      );
    }
    if (response.headers.get('x-well-data') === 'true' && parsed?.props) {
      const { csrfToken, i18n, ...props } = parsed.props;
      return { status, redirect, data: { component: parsed.component, props } };
    }
    return { status, redirect, data: parsed };
  };
}
