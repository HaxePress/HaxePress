import { createServer } from 'node:http';
import { timingSafeEqual } from 'node:crypto';
import { createInterface } from 'node:readline';
import {
  createMcpHandler,
  isLegacyRequest,
  PROTOCOL_VERSION_META_KEY,
  WebStandardStreamableHTTPServerTransport,
} from '@modelcontextprotocol/server';
import { createThemeServer } from './factory';
import { MAX_MCP_REQUEST_BYTES } from '../resources/js/themes/builder/types';

interface Bootstrap {
  secret: string;
  origin: string;
}
const lines = createInterface({ input: process.stdin, crlfDelay: Infinity });
const bootstrap = await new Promise<Bootstrap>((resolve, reject) => {
  const timeout = setTimeout(() => reject(new Error('Missing site bootstrap.')), 5000);
  lines.once('line', (line) => {
    clearTimeout(timeout);
    if (line.length > 2048) return reject(new Error('Invalid site bootstrap.'));
    try {
      resolve(JSON.parse(line));
    } catch {
      reject(new Error('Invalid site bootstrap.'));
    }
  });
});
if (!/^[A-Za-z0-9_-]{32}$/.test(bootstrap.secret)) throw new Error('Invalid bridge key.');
const bridgeKey = Buffer.from(bootstrap.secret);
const maxBody = MAX_MCP_REQUEST_BYTES;
const maxResponse = 10 * 1024 * 1024;
const headersToForward = [
  'accept',
  'content-type',
  'mcp-protocol-version',
  'mcp-method',
  'mcp-name',
  'mcp-session-id',
];
const activeRequests = new Set<AbortController>();

const server = createServer(async (incoming, outgoing) => {
  const key = Buffer.from(String(incoming.headers['x-haxepress-bridge'] || ''));
  if (key.length !== bridgeKey.length || !timingSafeEqual(key, bridgeKey)) {
    outgoing.writeHead(403).end();
    return;
  }
  const match = /^\/themes\/(theme-[a-z0-9]+(?:-[a-z0-9]+)*)$/.exec(incoming.url || '');
  const authorization = incoming.headers.authorization || '';
  if (!match || match[1].length > 80 || !/^Bearer hx[pb]_[A-Za-z0-9_-]{32}$/.test(authorization)) {
    outgoing.writeHead(400).end();
    return;
  }
  const controller = new AbortController();
  activeRequests.add(controller);
  const timeout = setTimeout(() => controller.abort(), 25000);
  outgoing.once('close', () => {
    if (!outgoing.writableFinished) controller.abort();
  });
  let closeInstance: (() => Promise<void>) | undefined;
  try {
    const chunks: Buffer[] = [];
    let size = 0;
    for await (const chunk of incoming) {
      size += chunk.length;
      if (size > maxBody) {
        outgoing.writeHead(413).end();
        return;
      }
      chunks.push(chunk);
    }
    const permissions = JSON.parse(String(incoming.headers['x-haxepress-permissions'] || 'null'));
    if (
      !permissions ||
      !['read', 'edit', 'media'].every((key) => typeof permissions[key] === 'boolean')
    ) {
      outgoing.writeHead(403).end();
      return;
    }
    const headers = new Headers();
    for (const name of headersToForward) {
      const value = incoming.headers[name];
      if (typeof value === 'string') headers.set(name, value);
    }
    const body = Buffer.concat(chunks);
    if (incoming.headers['x-haxepress-transport'] === 'websocket') {
      // A WebSocket frame has no per-message HTTP headers. Mirror its metadata
      // for the SDK's HTTP adapter; the SDK still validates and dispatches it.
      try {
        const message = JSON.parse(body.toString());
        const revision = message.params?._meta?.[PROTOCOL_VERSION_META_KEY];
        if (typeof revision === 'string') headers.set('MCP-Protocol-Version', revision);
        if (typeof message.method === 'string') headers.set('Mcp-Method', message.method);
        const field = message.method === 'resources/read' ? 'uri' : 'name';
        const name = message.params?.[field];
        if (typeof name === 'string') {
          headers.set('Mcp-Name', '=?base64?' + Buffer.from(name).toString('base64') + '?=');
        }
      } catch {
        // Malformed JSON is returned to the SDK's own parse-error handler.
      }
    }
    const method = incoming.method || 'POST';
    const request = new Request('http://haxepress.internal/mcp', {
      method,
      headers,
      signal: controller.signal,
      ...(method === 'POST' ? { body } : {}),
    });
    const factory = () =>
      createThemeServer({
        origin: bootstrap.origin,
        themeId: match[1],
        token: authorization.slice(7),
        signal: controller.signal,
        permissions,
      });
    let response: Response;
    if (
      method === 'POST' &&
      (await isLegacyRequest(request, undefined, { maxRequestBodySize: maxBody }))
    ) {
      const instance = factory();
      const transport = new WebStandardStreamableHTTPServerTransport({
        sessionIdGenerator: undefined,
        enableJsonResponse: true,
        maxRequestBodySize: maxBody,
      });
      closeInstance = () => instance.close();
      controller.signal.addEventListener('abort', () => void instance.close(), { once: true });
      await instance.connect(transport);
      response = await transport.handleRequest(request);
    } else {
      const handler = createMcpHandler(factory, {
        legacy: 'reject',
        responseMode: 'json',
        maxRequestBodySize: maxBody,
      });
      response = await handler.fetch(request);
    }
    const bytes: Uint8Array[] = [];
    let length = 0;
    if (response.body) {
      const reader = response.body.getReader();
      while (true) {
        const chunk = await reader.read();
        if (chunk.done) break;
        length += chunk.value.length;
        if (length > maxResponse) {
          await reader.cancel();
          throw new Error('MCP response limit exceeded.');
        }
        bytes.push(chunk.value);
      }
    }
    const responseHeaders: Record<string, string> = { 'cache-control': 'private, no-store' };
    for (const name of ['content-type', 'allow', 'mcp-protocol-version', 'mcp-session-id']) {
      const value = response.headers.get(name);
      if (value) responseHeaders[name] = value;
    }
    outgoing.writeHead(response.status, responseHeaders).end(Buffer.concat(bytes));
  } catch {
    if (!outgoing.headersSent) outgoing.writeHead(503, { 'content-type': 'application/json' });
    outgoing.end(JSON.stringify({ error: 'The site MCP service is unavailable.' }));
  } finally {
    clearTimeout(timeout);
    activeRequests.delete(controller);
    await closeInstance?.();
  }
});
server.requestTimeout = 30000;
server.headersTimeout = 10000;
server.keepAliveTimeout = 1000;
server.listen(0, '127.0.0.1', () => {
  const address = server.address();
  if (!address || typeof address === 'string') throw new Error('MCP listener did not start.');
  process.stdout.write(JSON.stringify({ port: address.port }) + '\n');
});
function stop() {
  for (const controller of activeRequests) controller.abort();
  server.close();
  server.closeAllConnections();
  lines.close();
  process.stdin.destroy();
}
process.once('SIGTERM', stop);
process.stdin.once('end', stop);
