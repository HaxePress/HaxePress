# Theme collaboration and MCP

HaxePress owns the theme MCP service. A browser editor and an external LLM join the same theme channel through native HxWell WebSockets. The browser receives saved-draft changes immediately; it no longer polls for revisions. The editor keeps local unsaved work intact and offers **Load saved design** when a remote edit conflicts with it. AI writes save drafts; publishing remains an editor action.

No MCP server process, script download, stdio setup or Node.js installation is required on the client's computer. The site's JVM starts and stops its private protocol SDK worker. Build that worker with `npm run build:mcp`; Node.js 22.12+ is a server prerequisite. The worker is loopback-only, has an ephemeral internal bridge key, and is not an additional public endpoint.

## The two connections

| Peer | WebSocket path | Authentication |
| --- | --- | --- |
| Browser editor | `/admin/themes/{theme-id}/ai/ws` | The native `admin` guard, current session and trusted Origin. |
| External LLM | `/mcp/themes/{theme-id}/ws` | A theme-scoped `Authorization: Bearer <connection key>` header. |

Browser tools work without creating an external LLM key. The browser never receives the internal bridge credential, another user's key or its own session identifier through the page API. A server-only, short-lived credential links SDK requests back to the native browser session. Every message and private data operation rechecks authentication, the current account/password, theme scope and permissions. Logout, account deactivation and password changes invalidate browser access. Unauthenticated connections and untrusted browser origins are rejected.

External keys expire after 24 hours. Only their SHA-256 hashes are stored. Creating a replacement or choosing **Revoke connection** closes the affected LLM sockets and invalidates the previous key. Account deactivation, loss of theme-management permission and password changes also invalidate it. Keys never authorize ordinary admin routes.

**Connect AI** shows browser/LLM connection state, AI permissions, the external WebSocket URL and explicit key creation/revocation. It supplies connection details, not a client-side server configuration. Use `ws://` locally and `wss://` behind HTTPS. Clients must support this custom WebSocket transport and the Authorization upgrade header. A Streamable HTTP compatibility endpoint remains at `/mcp/themes/{theme-id}` for standard MCP clients.

## Permissions

`theme_ai_permissions` stores one policy per administrator and theme. Native roles remain the upper bound. The same policy controls that administrator's browser tools and external connections:

| Permission | Tools |
| --- | --- |
| Read design | `get_design_guide`, `get_design`, `get_collection_schema`, `search_theme_assets`, `read_theme_asset_image` and the guide resource. |
| Edit design draft | `edit_design`, `replace_design`, `upload_theme_image`, `verify_theme_image`; requires Read design. |
| Browse media | `search_media`, `read_media_image`; requires Read design and the account's media capability. |

An absent policy preserves the account's existing theme-management and media permissions. Saving a policy uses native handler validation, CSRF, an ORM upsert and a query-specific typed cache. It does not rotate or create a key. Permission changes are pushed to browser peers; their WebMCP registrations are updated. The server filters discovery/tool lists and enforces permissions again on calls and data writes. Client-supplied permission headers are ignored.

These controls govern the CMS's AI tools. They do not change the signed-in administrator's ordinary editing permissions or the broader access a browser extension may already have to a page.

## JavaScript and browser extensions

While an authenticated theme editor is open, extensions capable of executing page JavaScript can use:

```js
const designer = window.haxePress.themeDesigner;
const tools = await designer.listTools();
const result = await designer.callTool('get_design');
const { theme } = result.structuredContent;

await designer.callTool('edit_design', {
  expectedVersion: theme.version,
  operations: [{ action: 'tokens', values: { accent: '#134e4a' } }],
});
```

The read-only `permissions` property describes the current server policy. `getContext()` reports the current theme, saved version, dirty state, selected scope and selection. `callTool(name, arguments, {signal})` accepts an optional AbortSignal. Results use the normal MCP content/structured-content shape. The editor requires local changes to be saved before running an AI design edit. Retained API references, registered tools and connections are cleaned up when the editor unmounts.

When WebMCP is available, these same definitions are registered as `haxepress_get_design`, `haxepress_edit_design`, etc. The implementation uses `document.modelContext` and supports the older navigator-based API when supplied by a browser. No WebMCP polyfill is installed. Extensions can use the page API even without native WebMCP support; exact integration depends on the browser and extension.

## Wire behavior

Each UTF-8 text frame contains one JSON-RPC message. The official MCP SDK handles legacy handshakes and the 2026-07-28 per-request envelope. Responses retain request IDs; notifications have no response. Binary frames are unsupported. The browser's SDK discovery heartbeat revalidates its session. Reconnection performs one bounded revision read to catch changes missed while disconnected, without recurring HTTP polling.

Browser peers receive these authenticated, theme-scoped notifications:

| Method | Parameters |
| --- | --- |
| `notifications/haxepress/design_changed` | `themeId`, `version`, `publishedVersion` |
| `notifications/haxepress/permissions` | `themeId`, `permissions: {read, edit, media}` |
| `notifications/haxepress/presence` | `browsers`, `llms` |

Only revision metadata is broadcast. The browser fetches the relevant cached snapshot through its guarded endpoint. Another theme's peers receive no update. Failed validation, stale expected versions and denied operations do not save or emit design changes. Backend operations are bounded and cancellation is best-effort once a write has begun.

The tools reuse the visual editor's schema, operations, managed-media checks and native `ThemeStudio.save` path. Inserts/moves/clones use stable IDs and cycle prevention. Each write supplies `expectedVersion`. Search uses bounded cursor pages, collection tools return public schema metadata, and image reads respect the native 5 MB limit. No shell, grant-management or publishing tools are exposed.

`MCP_HOST_ENABLED=false` disables the hosted service. `NODE_BINARY` selects the server runtime. Origins default to `APP_URL`; `MCP_ALLOWED_ORIGINS` adds explicit comma-separated origins. Requests without an Origin remain available to authenticated native LLM clients; browser sockets require an allowed Origin. Remote deployments should use HTTPS/WSS.

## Verification

Run `python3 tests/run.py --only theme_mcp` after building native packages and the SDK host. It covers official HTTP/WebSocket clients in both protocol eras, large image delivery, real draft edits, hashed/scoped/expiring keys, live revocation, browser-session authentication, channel isolation, permission enforcement, JavaScript/WebMCP delegation, dirty-work protection, logout and teardown. The browser-API integration uses the actual browser connection/registration modules with the native server and a deterministic WebMCP host; visual QA checks the real editor. JVM shutdown must also terminate its protocol worker.

See [WebSocket lifecycle](WEBSOCKET-LIFECYCLE.md) for transport cleanup regressions. Protocol references: [MCP transports](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports) and [WebMCP draft](https://webmachinelearning.github.io/webmcp/).

Theme-owned image tools and portable Storage are described in [theme assets](THEME-ASSETS.md).
