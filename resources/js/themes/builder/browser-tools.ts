import type {
  ThemeDesignerConnection,
  DesignerResult,
  DesignerTool,
  AiPermissions,
} from './ThemeDesignerConnection';
import type { AdminMcpBrowserApi } from '../../ai/AdminMcpBrowser';

export interface DesignerContext {
  themeId: string;
  version: number;
  dirty: boolean;
  scope: string;
  selection: unknown;
}
export interface ThemeDesignerApi {
  readonly themeId: string;
  readonly permissions: AiPermissions;
  getContext(): DesignerContext;
  listTools(): Promise<DesignerTool[]>;
  callTool(
    name: string,
    args?: Record<string, unknown>,
    options?: { signal?: AbortSignal },
  ): Promise<DesignerResult>;
}

interface BrowserModelContext {
  registerTool(
    tool: {
      name: string;
      description: string;
      inputSchema: object;
      annotations: {
        readOnlyHint: boolean;
        untrustedContentHint: boolean;
        consequentialHint: boolean;
      };
      execute: (
        args: Record<string, unknown>,
        options?: { signal?: AbortSignal },
      ) => Promise<unknown>;
    },
    options?: { signal: AbortSignal },
  ): Promise<void> | void;
  unregisterTool?(name: string): void;
}

declare global {
  interface Window {
    haxePress?: { themeDesigner?: ThemeDesignerApi; adminMcp?: AdminMcpBrowserApi };
  }
  interface Document {
    modelContext?: BrowserModelContext;
  }
  interface Navigator {
    modelContext?: BrowserModelContext;
  }
}

/** The extension-facing API calls the same authenticated server tools as external LLMs. */
export function installBrowserTools(
  connection: ThemeDesignerConnection,
  getContext: () => DesignerContext,
  canChange: () => boolean,
): () => void {
  const api: ThemeDesignerApi = Object.freeze({
    themeId: connection.themeId,
    get permissions() {
      return Object.freeze({ ...connection.permissions });
    },
    getContext: () => structuredClone(getContext()),
    listTools: () => connection.listTools(),
    callTool: async (
      name: string,
      args: Record<string, unknown> = {},
      options?: { signal?: AbortSignal },
    ) => {
      if (['edit_design', 'replace_design'].includes(name) && !canChange()) {
        throw new Error('Save your local changes before applying an AI edit.');
      }
      return connection.callTool(name, args, options?.signal);
    },
  });
  window.haxePress ||= {};
  Object.defineProperty(window.haxePress, 'themeDesigner', {
    configurable: true,
    enumerable: true,
    value: api,
  });
  const context = document.modelContext || navigator.modelContext;
  let registration: AbortController | null = null;
  let names: string[] = [];
  let generation = 0;
  let disposed = false;

  function clear() {
    registration?.abort();
    for (const name of names) context?.unregisterTool?.(name);
    names = [];
  }
  async function register() {
    const current = ++generation;
    clear();
    if (!context || connection.status !== 'connected' || !connection.permissions.read) return;
    const tools = await api.listTools();
    if (disposed || current !== generation) return;
    const controller = new AbortController();
    registration = controller;
    for (const tool of tools) {
      const name = `haxepress_${tool.name}`;
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
          execute: (args, options) => api.callTool(tool.name, args, options),
        },
        { signal: controller.signal },
      );
      if (disposed || current !== generation) {
        context.unregisterTool?.(name);
        return;
      }
      names.push(name);
    }
  }
  const unsubscribe = connection.subscribe((event) => {
    if (event.type === 'permissions' || event.type === 'state') void register().catch(clear);
  });
  void register().catch(clear);
  return () => {
    disposed = true;
    generation++;
    unsubscribe();
    clear();
    if (window.haxePress?.themeDesigner === api) delete window.haxePress.themeDesigner;
  };
}
