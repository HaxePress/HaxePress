# Admin MCP and theme collaboration

**Connect AI** is available throughout the administration panel. A signed-in admin page opens its browser WebSocket automatically. Select **Web** for the English JavaScript prompt or generate a Streamable HTTP connection for ChatGPT desktop, Claude, Codex or another MCP client.

The site's JVM starts and stops its private SDK worker. Build the worker with `npm run build:mcp`. Node.js 22.12+ is a server prerequisite. The worker listens on loopback with an internal credential.

## Connection setup

Each generated connection has a unique `/mcp/sessions/{id}` URL and bearer token. The token is bound to that URL and must be sent in the `Authorization` header on each request. The session expires after 24 hours or when the administrator selects **Revoke session**. Restarting the JVM clears the process's sessions. MCP uses the administrator's current permissions for every action. [MCP authorization](https://modelcontextprotocol.io/specification/2026-07-28/basic/authorization)

The session list shows the first and most recent authenticated requests that the server answered successfully. New sessions show **Not used yet**. The open dialog refreshes this information every ten seconds.

- **ChatGPT / Codex** provides a `[mcp_servers.<name>]` entry for the `~/.codex/config.toml` file shared by ChatGPT desktop and Codex on the same host. Add the entry and restart the client. Select **Codex CLI** to get a shell command and bearer environment variable for the same connection. [ChatGPT MCP guide](https://learn.chatgpt.com/docs/extend/mcp?surface=app), [Codex CLI reference](https://learn.chatgpt.com/docs/cli/reference#codex-mcp)
- **Claude** generates a `claude mcp add --transport http` command. Claude web accepts the URL and bearer header in a custom connector when the HaxePress server is reachable over HTTPS. [Claude Code MCP](https://code.claude.com/docs/en/mcp), [Claude custom connectors](https://support.claude.com/en/articles/11175166-get-started-with-custom-connectors-using-remote-mcp)
- **Gemini CLI** generates a `gemini mcp add` command with the HTTP transport, bearer header and user scope. [Gemini CLI MCP](https://geminicli.com/docs/tools/mcp-server/#adding-an-http-server)
- **Cursor** generates an entry for the global `~/.cursor/mcp.json` configuration. [Cursor MCP setup](https://prod.cursor.com/help/customization/mcp)
- **GitHub Copilot** generates the portable HTTP entry for the Copilot user `mcp-config.json`. [VS Code MCP configuration](https://code.visualstudio.com/docs/agents/reference/mcp-configuration#portable-configuration)
- **Grok API** generates a remote MCP tool object for the xAI Responses API. Use an HTTPS endpoint reachable from xAI. [xAI remote MCP](https://docs.x.ai/developers/tools/remote-mcp)
- **Other MCP clients** get a Streamable HTTP URL and header configuration.

Use the site HTTPS origin configured in `APP_URL` for deployments. Local desktop clients can use loopback HTTP. Browser WebSockets require a trusted origin. `MCP_ALLOWED_ORIGINS` adds explicit comma-separated origins. `MCP_HOST_ENABLED=false` disables the hosted service and `NODE_BINARY` selects the server runtime.

## Admin tools

The catalog includes content and revisions, categories and tags, the media library, themes, plugins, navigation, site settings, account views and backup schedule status. The tools call the same guarded controllers and validators as the panel. Use `get_admin_routes`, `read_admin` and `write_admin` for other permitted native routes. Credentials, role grants, package installation, backup archive downloads and theme publishing are managed interactively.

Use `upload_media_image` to stage JPEG, PNG or GIF bytes. Review the echoed image, then call `verify_media_image` with its upload ID, SHA-256 and measured pixel dimensions. The verified media ID is accepted by `set_content_cover` and `insert_content_image`. Content edits require the current item version and preserve existing fields. Save an open working copy in the editor before editing through MCP.

The upload tools accept canonical Base64 or an image attachment supplied by a host that supports the file input metadata. The worker retrieves a bounded attachment from the ChatGPT content domain and sends the original bytes through the same HaxePress staging and verification flow. [OpenAI Docs file inputs](https://developers.openai.com/plugins/reference#define-file-inputs)

## Theme tools

Use `list_themes` to get a theme ID. `inspect_theme_tree` returns template, component, section and block IDs, and `get_theme_section` reads a specific section with its styles and bindings. `get_theme_design_guide` describes the schema. Use `edit_theme_design` for atomic changes or `replace_theme_design` for a whole draft. Every edit requires the expected saved version.

`upload_theme_image` stages a theme-owned image. Review its preview and pass its ID, SHA-256 and measured dimensions to `verify_theme_image`. Use the resulting managed URL with `set_theme_block_image`. Theme-owned assets live in the theme storage and travel with its export.

The same per-theme read, draft edit and shared media permissions apply to remote and browser clients. A permission change takes effect on the next operation and updates the scoped browser tools. The editor receives live draft revisions and offers **Load saved design** when an external edit conflicts with unsaved work.

## Browser JavaScript

A browser extension can run tools from the signed-in administration page.

```js
const admin = window.haxePress.adminMcp;
const { path } = admin.getContext();
const tools = await admin.listTools();
const result = await admin.callTool('list_themes', {});
```

The theme editor also exposes `window.haxePress.themeDesigner` with tools scoped to the current theme. It reports the current selection, saved version and dirty state. The browser registers `haxepress_admin_*` and scoped theme tools when WebMCP is available. [WebMCP draft](https://webmachinelearning.github.io/webmcp/)

## Plugin tools

Plugins register an MCP tool by annotating a concrete route inside `host.admin` with `cms.mcp`. The declaration includes a name, description, capability and JSON object input schema. HaxePress namespaces the name with the plugin slug and checks the capability on each call. The catalog follows the installed plugin's lifecycle. [Plugin package API](PLUGIN-PACKAGES.md#mcp-tools)

## Verification

Run `python3 tests/run.py --only admin_mcp`, `python3 tests/run.py --only theme_mcp` and `python3 tests/run.py --only cms_lifecycle` after building the JVM and SDK worker. These suites cover bearer binding and revocation, standard SDK clients, native admin actions, verified content and theme uploads, browser tool permissions, live revisions and plugin registration.
