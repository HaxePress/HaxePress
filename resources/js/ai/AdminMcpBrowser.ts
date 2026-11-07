import { Client } from '@modelcontextprotocol/client';
import {
  BrowserHttpTransport,
  BrowserSocketTransport,
} from '../themes/builder/ThemeDesignerConnection';
import type {} from '../themes/builder/browser-tools';

export type AdminMcpStatus = 'connecting' | 'connected' | 'disconnected';

export interface AdminMcpBrowserApi {
  getContext(): { path: string; title: string };
  listTools(): Promise<Awaited<ReturnType<Client['listTools']>>['tools']>;
  callTool(
    name: string,
    args?: Record<string, unknown>,
    options?: { signal?: AbortSignal },
  ): ReturnType<Client['callTool']>;
}

/**
 * Connects the signed-in page to the site's admin MCP tools. Without
 * WebSockets (`websocket: false`, as on PHP) each message is an HTTP POST to
 * the same address, and the caller refreshes its state by polling.
 */
export function startAdminMcp(
  onStatus: (status: AdminMcpStatus) => void,
  onChange: () => void,
  websocket = true,
): () => void {
  const url = new URL('/admin/ai/ws', location.origin);
  if (websocket) url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:';
  const context = document.modelContext || navigator.modelContext;
  let stopped = false;
  let client: Client | null = null;
  let api: AdminMcpBrowserApi | null = null;
  let retries = 0;
  let retry: ReturnType<typeof setTimeout> | undefined;
  let heartbeat: ReturnType<typeof setInterval> | undefined;
  let registration: AbortController | undefined;
  const names = new Set<string>();

  function clear() {
    clearInterval(heartbeat);
    registration?.abort();
    for (const name of names) context?.unregisterTool?.(name);
    names.clear();
    if (window.haxePress?.adminMcp === api && window.haxePress) delete window.haxePress.adminMcp;
    api = null;
  }

  function disconnected(previous: Client) {
    if (client !== previous) return;
    client = null;
    clear();
    onStatus('disconnected');
    if (!stopped) {
      const delay = Math.min(10000, 500 * 2 ** Math.min(retries++, 5));
      retry = setTimeout(() => void connect(), delay);
    }
  }

  async function registerTools(active: Client, browserApi: AdminMcpBrowserApi) {
    if (!context) return;
    const controller = new AbortController();
    registration = controller;
    const tools = await browserApi.listTools();
    for (const tool of tools) {
      if (stopped || client !== active || controller.signal.aborted) return;
      const name = `haxepress_admin_${tool.name}`;
      names.add(name);
      await context.registerTool(
        {
          name,
          description: tool.description || tool.name,
          inputSchema: tool.inputSchema,
          annotations: {
            readOnlyHint: tool.annotations?.readOnlyHint === true,
            untrustedContentHint: true,
            consequentialHint: tool.annotations?.readOnlyHint !== true,
          },
          execute: (args, options) => browserApi.callTool(tool.name, args, options),
        },
        { signal: controller.signal },
      );
      if (controller.signal.aborted) context.unregisterTool?.(name);
    }
  }

  async function connect() {
    if (stopped) return;
    onStatus('connecting');
    const active = new Client(
      { name: 'haxepress-browser-admin', version: '1.0.0' },
      { versionNegotiation: { mode: { pin: '2026-07-28' } } },
    );
    client = active;
    active.onclose = () => disconnected(active);
    const transport = websocket
      ? new BrowserSocketTransport(url, (method) => {
          if (method === 'notifications/haxepress/admin_ai_changed') onChange();
        })
      : new BrowserHttpTransport(url);
    try {
      await active.connect(transport);
      if (stopped || client !== active) {
        await active.close();
        return;
      }
    } catch {
      disconnected(active);
      await active.close().catch(() => {});
      return;
    }
    retries = 0;
    const browserApi: AdminMcpBrowserApi = Object.freeze({
      getContext: () => ({ path: location.pathname + location.search, title: document.title }),
      listTools: async () => (await active.listTools()).tools,
      callTool: (
        name: string,
        args: Record<string, unknown> = {},
        options?: { signal?: AbortSignal },
      ) => active.callTool({ name, arguments: args }, options),
    });
    api = browserApi;
    window.haxePress ||= {};
    Object.defineProperty(window.haxePress, 'adminMcp', {
      configurable: true,
      enumerable: true,
      value: browserApi,
    });
    onStatus('connected');
    onChange();
    heartbeat = setInterval(() => void active.discover().catch(() => active.close()), 25000);
    void registerTools(active, browserApi).catch(() => registration?.abort());
  }

  void connect();
  return () => {
    stopped = true;
    clearTimeout(retry);
    const active = client;
    client = null;
    clear();
    void active?.close().catch(() => {});
  };
}
