import { MAX_MCP_REQUEST_BYTES } from './types';
import {
  Client,
  type JSONRPCMessage,
  type Transport,
  type TransportSendOptions,
} from '@modelcontextprotocol/client';

export interface AiPermissions {
  read: boolean;
  edit: boolean;
  media: boolean;
}
export interface DesignerPresence {
  browsers: number;
}
export interface DesignChange {
  themeId: string;
  version: number;
  publishedVersion: number;
}
export type DesignerTool = Awaited<ReturnType<Client['listTools']>>['tools'][number];
export type DesignerResult = Awaited<ReturnType<Client['callTool']>>;
export type DesignerStatus = 'connecting' | 'connected' | 'disconnected';
export type DesignerEvent =
  | { type: 'state' }
  | { type: 'presence' }
  | { type: 'design_changed'; change: DesignChange }
  | { type: 'permissions' };

export class BrowserSocketTransport implements Transport {
  onclose?: () => void;
  onerror?: (error: Error) => void;
  onmessage?: (message: JSONRPCMessage) => void;
  socket: WebSocket | null = null;
  closeCode = 1006;

  constructor(
    private readonly url: URL,
    private readonly notification: (method: string, params: unknown) => void,
  ) {}

  async start(): Promise<void> {
    const socket = new WebSocket(this.url);
    this.socket = socket;
    socket.addEventListener('message', (event) => {
      if (typeof event.data !== 'string' || event.data.length > 10 * 1024 * 1024) {
        socket.close();
        return;
      }
      try {
        const message = JSON.parse(event.data);
        if (
          typeof message.method === 'string' &&
          message.method.startsWith('notifications/haxepress/')
        ) {
          this.notification(message.method, message.params);
        } else {
          this.onmessage?.(message);
        }
      } catch {
        this.onerror?.(new Error('An invalid collaboration message was received.'));
        socket.close();
      }
    });
    socket.addEventListener('close', (event) => {
      this.closeCode = event.code;
      this.onclose?.();
    });
    socket.addEventListener('error', () =>
      this.onerror?.(new Error('The collaboration connection failed.')),
    );
    await new Promise<void>((resolve, reject) => {
      const timeout = setTimeout(() => {
        socket.close();
        reject(new Error('The collaboration connection timed out.'));
      }, 10000);
      socket.addEventListener(
        'open',
        () => {
          clearTimeout(timeout);
          resolve();
        },
        { once: true },
      );
      socket.addEventListener(
        'error',
        () => {
          clearTimeout(timeout);
          reject(new Error('The collaboration connection failed.'));
        },
        { once: true },
      );
    });
  }

  async send(message: JSONRPCMessage, _options?: TransportSendOptions): Promise<void> {
    if (this.socket?.readyState !== WebSocket.OPEN)
      throw new Error('The collaboration connection is closed.');
    const source = JSON.stringify(message);
    if (new TextEncoder().encode(source).length > MAX_MCP_REQUEST_BYTES) {
      throw new Error('The design request exceeds its size limit.');
    }
    this.socket.send(source);
  }

  async close(): Promise<void> {
    const socket = this.socket;
    if (!socket || socket.readyState === WebSocket.CLOSED) return;
    await new Promise<void>((resolve) => {
      const timeout = setTimeout(resolve, 1000);
      socket.addEventListener(
        'close',
        () => {
          clearTimeout(timeout);
          resolve();
        },
        { once: true },
      );
      socket.close();
    });
  }
}

/** The admin session's CSRF token, which the site keeps in a readable cookie. */
function csrfToken(): string {
  const match = /(?:^|;\s*)XSRF-TOKEN=([^;]*)/.exec(document.cookie);
  return match ? decodeURIComponent(match[1]) : '';
}

/**
 * Sends each MCP message as an HTTP POST to the socket's address, for sites
 * that run without WebSockets, such as the PHP build. The server answers
 * every request with its JSON-RPC reply; there are no pushed notifications,
 * so callers poll for changes.
 */
export class BrowserHttpTransport implements Transport {
  onclose?: () => void;
  onerror?: (error: Error) => void;
  onmessage?: (message: JSONRPCMessage) => void;
  closeCode = 1000;
  private closed = false;

  constructor(private readonly url: URL) {}

  async start(): Promise<void> {}

  async send(message: JSONRPCMessage, _options?: TransportSendOptions): Promise<void> {
    if (this.closed) throw new Error('The collaboration connection is closed.');
    const source = JSON.stringify(message);
    if (new TextEncoder().encode(source).length > MAX_MCP_REQUEST_BYTES) {
      throw new Error('The design request exceeds its size limit.');
    }
    const response = await fetch(this.url, {
      method: 'POST',
      credentials: 'same-origin',
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/json',
        'X-XSRF-TOKEN': csrfToken(),
      },
      body: source,
      signal: AbortSignal.timeout(30000),
    });
    if (response.status === 202 || response.status === 204) return;
    const reply = response.headers.get('content-type')?.includes('application/json')
      ? await response.json().catch(() => null)
      : null;
    if (response.redirected || !reply || reply.jsonrpc !== '2.0') {
      // A signed-out session or a revoked permission ends the connection, as a closed socket does.
      this.closeCode = 1008;
      await this.close();
      throw new Error('The collaboration connection is closed.');
    }
    this.onmessage?.(reply);
  }

  async close(): Promise<void> {
    if (this.closed) return;
    this.closed = true;
    this.onclose?.();
  }
}

interface ConnectionInfo {
  permissions: AiPermissions;
  presence: DesignerPresence;
  websocket: boolean;
}

/** How often an editor without WebSockets checks for permission and draft changes. */
const POLL_MS = 10000;

/** A browser is an authenticated peer of the site's theme MCP, never a server process. */
export class ThemeDesignerConnection {
  status: DesignerStatus = 'disconnected';
  permissions: AiPermissions = { read: false, edit: false, media: false };
  presence: DesignerPresence = { browsers: 0 };
  private client: Client | null = null;
  private pending: Promise<Client> | null = null;
  private stopped = false;
  private retries = 0;
  private retry: ReturnType<typeof setTimeout> | null = null;
  private heartbeat: ReturnType<typeof setInterval> | null = null;
  private poll: ReturnType<typeof setInterval> | null = null;
  private version: DesignChange | null = null;
  private readonly listeners = new Set<(event: DesignerEvent) => void>();

  constructor(readonly themeId: string) {}

  private path(suffix: string): string {
    return `/admin/themes/${encodeURIComponent(this.themeId)}${suffix}`;
  }

  private async read<T>(suffix: string): Promise<T | null> {
    try {
      const response = await fetch(this.path(suffix), {
        headers: { Accept: 'application/json' },
        signal: AbortSignal.timeout(10000),
      });
      if (!response.ok || response.redirected) return null;
      return (await response.json()) as T;
    } catch {
      return null;
    }
  }

  /** Without WebSockets, permission, presence and draft changes arrive by polling. */
  private async refresh(): Promise<void> {
    const info = await this.read<ConnectionInfo>('/ai');
    if (info) {
      this.notification('notifications/haxepress/permissions', {
        themeId: this.themeId,
        permissions: info.permissions,
      });
      if (info.presence.browsers !== this.presence.browsers)
        this.notification('notifications/haxepress/presence', info.presence);
    }
    const status = await this.read<{ version: number; publishedVersion: number }>('/design/status');
    if (!status) return;
    const change = { themeId: this.themeId, ...status };
    const previous = this.version;
    this.version = change;
    if (
      previous &&
      (previous.version !== change.version || previous.publishedVersion !== change.publishedVersion)
    )
      this.notification('notifications/haxepress/design_changed', change);
  }

  subscribe(listener: (event: DesignerEvent) => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  private emit(event: DesignerEvent) {
    for (const listener of this.listeners) listener(event);
  }

  private notification(method: string, params: unknown) {
    if (!params || typeof params !== 'object') return;
    const data = params as Record<string, unknown>;
    if (method === 'notifications/haxepress/permissions' && data.themeId === this.themeId) {
      const permissions = data.permissions as AiPermissions | undefined;
      if (
        !permissions ||
        !['read', 'edit', 'media'].every(
          (key) => typeof permissions[key as keyof AiPermissions] === 'boolean',
        )
      )
        return;
      const changed =
        this.permissions.read !== permissions.read ||
        this.permissions.edit !== permissions.edit ||
        this.permissions.media !== permissions.media;
      this.permissions = { ...permissions };
      if (changed) this.emit({ type: 'permissions' });
    }
    if (method === 'notifications/haxepress/presence' && Number.isSafeInteger(data.browsers)) {
      this.presence = { browsers: Number(data.browsers) };
      this.emit({ type: 'presence' });
    }
    if (
      method === 'notifications/haxepress/design_changed' &&
      data.themeId === this.themeId &&
      Number.isSafeInteger(data.version) &&
      Number.isSafeInteger(data.publishedVersion)
    ) {
      this.emit({ type: 'design_changed', change: data as unknown as DesignChange });
    }
  }

  async ready(): Promise<Client> {
    if (this.status === 'connected' && this.client) return this.client;
    if (this.pending) return this.pending;
    if (this.stopped) throw new Error('The collaboration connection is closed.');
    this.status = 'connecting';
    this.emit({ type: 'state' });
    this.pending = this.open().finally(() => {
      this.pending = null;
    });
    return this.pending;
  }

  private async open(): Promise<Client> {
    const info = await this.read<ConnectionInfo>('/ai');
    if (this.stopped) throw new Error('The collaboration connection is closed.');
    const url = new URL(this.path('/ai/ws'), location.origin);
    const polling = info?.websocket === false;
    let transport: BrowserSocketTransport | BrowserHttpTransport;
    if (polling) {
      transport = new BrowserHttpTransport(url);
    } else {
      url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:';
      transport = new BrowserSocketTransport(url, (method, params) =>
        this.notification(method, params),
      );
    }
    const client = new Client(
      { name: 'haxepress-browser-editor', version: '1.0.0' },
      { versionNegotiation: { mode: { pin: '2026-07-28' } } },
    );
    this.client = client;
    client.onclose = () => {
      if (this.client !== client) return;
      this.client = null;
      this.pending = null;
      this.permissions = { read: false, edit: false, media: false };
      this.presence = { browsers: 0 };
      this.status = 'disconnected';
      if (this.heartbeat) clearInterval(this.heartbeat);
      if (this.poll) clearInterval(this.poll);
      this.version = null;
      this.emit({ type: 'permissions' });
      this.emit({ type: 'state' });
      if (!this.stopped && transport.closeCode !== 1000 && this.retries < 5) {
        this.retries++;
        this.retry = setTimeout(
          () => void this.ready().catch(() => {}),
          Math.min(10000, 1000 * 2 ** this.retries),
        );
      }
    };
    try {
      await client.connect(transport);
      if (this.stopped || this.client !== client)
        throw new Error('The collaboration connection is closed.');
    } catch (error) {
      await client.close();
      throw error;
    }
    this.status = 'connected';
    this.retries = 0;
    this.heartbeat = setInterval(() => {
      void client.discover().catch(() => client.close());
    }, 25000);
    if (polling) {
      await this.refresh();
      this.poll = setInterval(() => void this.refresh(), POLL_MS);
    }
    this.emit({ type: 'state' });
    return client;
  }

  async listTools(): Promise<DesignerTool[]> {
    const client = await this.ready();
    if (!this.permissions.read) return [];
    return (await client.listTools()).tools;
  }

  async callTool(
    name: string,
    args: Record<string, unknown> = {},
    signal?: AbortSignal,
  ): Promise<DesignerResult> {
    const client = await this.ready();
    return client.callTool({ name, arguments: args }, signal ? { signal } : undefined);
  }

  reconnect(): void {
    if (this.retry) clearTimeout(this.retry);
    this.retries = 0;
    void this.ready().catch(() => {});
  }

  async close(): Promise<void> {
    this.stopped = true;
    if (this.retry) clearTimeout(this.retry);
    if (this.heartbeat) clearInterval(this.heartbeat);
    if (this.poll) clearInterval(this.poll);
    const client = this.client;
    this.client = null;
    await client?.close();
  }
}
