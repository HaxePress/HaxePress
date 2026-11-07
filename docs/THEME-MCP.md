# Admin MCP and theme collaboration

**Connect AI** is available throughout the administration panel. A signed-in admin page connects to the site's MCP tools automatically. Select **Web** for the English JavaScript prompt or generate a Streamable HTTP connection for ChatGPT desktop, Claude, Codex or another MCP client.

## How the server runs

The site serves MCP itself, on its own routes, with the same Haxe code in the JVM and PHP builds (`hx.press.mcp`); no other process takes part. Each POST to a link carries one JSON-RPC message and is answered with `application/json`. The server keeps no session or event stream between requests, so any process can answer any request, as PHP does with a new process for each one; GET and DELETE answer 405. It speaks the 2025 protocol revisions (after `initialize`) and the stateless 2026-07-28 revision (`server/discover`, with the protocol version in each request's `_meta`), whose `MCP-Protocol-Version`, `Mcp-Method` and `Mcp-Name` headers must agree with the body.

Tools reach the CMS through its own admin routes: each call is an in-process request through the route's middleware and handler, marked as an MCP request so that pages answer with their data. Nothing calls the site back over HTTP, and no internal ticket or bridge credential exists.

The signed-in admin page and the theme editor send their MCP messages over a WebSocket on the JVM, which also delivers change notices. The PHP build has no WebSockets: there the pages post each message to the same address (the WebSocket route's HTTP fallback) and poll for link, permission, presence and draft changes every ten seconds.

## Connection setup

Each generated connection has a unique `/mcp/sessions/{id}` URL and bearer token. The token is bound to that URL and must be sent in the `Authorization` header on each request. Choose how long the link lasts when you generate it: 1 hour, 1 day (the default), 7 days or 30 days. Until a client first connects, **Change expiry** sets a new expiry counted from now; after that it stays fixed. The session ends when it expires or when the administrator selects **Revoke session**. A URL that was never generated, or whose session was revoked, returns 404; a generated URL without its bearer token returns 401. Links are kept in the database (`admin_mcp_links`, which stores only a SHA-256 hash of each token), so they keep working across restarts and on PHP. MCP uses the administrator's current permissions for every action. [MCP authorization](https://modelcontextprotocol.io/specification/2026-07-28/basic/authorization)

The session list shows the first and most recent authenticated requests that the server answered successfully. New sessions show **Not used yet**. The open dialog refreshes this information every ten seconds.

- **ChatGPT / Codex** provides a `[mcp_servers.<name>]` entry for the `~/.codex/config.toml` file shared by ChatGPT desktop and Codex on the same host. Add the entry and restart the client. Select **Codex CLI** to get a shell command and bearer environment variable for the same connection. [ChatGPT MCP guide](https://learn.chatgpt.com/docs/extend/mcp?surface=app), [Codex CLI reference](https://learn.chatgpt.com/docs/cli/reference#codex-mcp)
- **Claude** generates a `claude mcp add --transport http` command. Claude web accepts the URL and bearer header in a custom connector when the HaxePress server is reachable over HTTPS. [Claude Code MCP](https://code.claude.com/docs/en/mcp), [Claude custom connectors](https://support.claude.com/en/articles/11175166-get-started-with-custom-connectors-using-remote-mcp)
- **Gemini CLI** generates a `gemini mcp add` command with the HTTP transport, bearer header and user scope. [Gemini CLI MCP](https://geminicli.com/docs/tools/mcp-server/#adding-an-http-server)
- **Cursor** generates an entry for the global `~/.cursor/mcp.json` configuration. [Cursor MCP setup](https://prod.cursor.com/help/customization/mcp)
- **GitHub Copilot** generates the portable HTTP entry for the Copilot user `mcp-config.json`. [VS Code MCP configuration](https://code.visualstudio.com/docs/agents/reference/mcp-configuration#portable-configuration)
- **Grok API** generates a remote MCP tool object for the xAI Responses API. Use an HTTPS endpoint reachable from xAI. [xAI remote MCP](https://docs.x.ai/developers/tools/remote-mcp)
- **Other MCP clients** get a Streamable HTTP URL and header configuration.

Use the site HTTPS origin configured in `APP_URL` for deployments. Local desktop clients can use loopback HTTP. Browser connections require a trusted origin. `MCP_ALLOWED_ORIGINS` adds explicit comma-separated origins.

## Admin tools

The catalog includes content and revisions, categories and tags, the media library, themes, plugins, navigation, site settings, account views and backup schedule status. The tools call the same guarded controllers and validators as the panel. Use `get_admin_routes`, `read_admin` and `write_admin` for other permitted native routes. Credentials, role grants, package installation, backup archive downloads and theme publishing are managed interactively.

An MCP link acts as the account that generated it, with that account's current role, and never more. Every request is checked twice: the MCP layer refuses requests outside the areas the role can open (settings, team, roles, themes and plugins, navigation, taxonomy, media, activity, content collections) before the page runs, and the page then applies its own checks, such as ownership and publishing rights. The tool list and `get_admin_routes` show only what the role allows. A role change applies to the link's next request; deactivating the account, changing its password or removing its role stops the link.

MCP clients can move content and images to the trash and restore them, but only people delete them permanently. Routes marked people-only, including every permanent delete, are refused for MCP requests and left out of `get_admin_routes`. Changes made through an MCP connection, including the browser and theme designer connections, appear on the Activity page and dashboard with a **Via MCP** mark.

Use `upload_media_image` to stage JPEG, PNG or GIF bytes. Review the echoed image, then call `verify_media_image` with its upload ID, SHA-256 and measured pixel dimensions. The verified media ID is accepted by `set_content_cover` and `insert_content_image`. Content edits require the current item version and preserve existing fields. Save an open working copy in the editor before editing through MCP.

The upload tools accept canonical Base64 or an image attachment supplied by a host that supports the file input metadata. The site retrieves a bounded attachment from the ChatGPT content domain and sends the original bytes through the same HaxePress staging and verification flow. [OpenAI Docs file inputs](https://developers.openai.com/plugins/reference#define-file-inputs)

## Theme tools

Use `list_themes` to get a theme ID. `inspect_theme_tree` returns template, component, section and block IDs, and `get_theme_section` reads a specific section with its styles and bindings. `get_theme_design_guide` describes the schema. Use `edit_theme_design` for atomic changes or `replace_theme_design` for a whole draft. Every edit requires the expected saved version.

`preview_theme_design` (`preview_theme` in a theme's own connection) shows the AI what visitors see. It renders a site page with the theme in a headless browser on the server and returns a JPEG with the page title, HTTP status, headings and the site paths it links to, so the AI can open further pages. Choose the page with `path` (such as `/`, `/content/a-post` or `/content?category=News`), the viewport with `device` (`desktop` 1280×800, `tablet` 834×1112 or `mobile` 390×844), the whole page instead of the first screen with `fullPage`, and the saved `draft` or the `published` design. The browser loads the admin theme preview with a one-minute pass that only reads that theme's preview pages and assets. It needs Chrome or Chromium on the server: Chrome's headless shell from the Puppeteer cache, an installed Chrome or Chromium, or the executable in `HAXEPRESS_CHROME`. `HAXEPRESS_CHROME_ARGS` adds browser flags, such as `--no-sandbox` in containers that do not allow its sandbox.

The preview runs on the JVM build only: the site starts the browser on the first capture, drives it over the DevTools protocol with its own Haxe client (`ThemePreviewBrowser`), keeps it for two idle minutes and stops it when the site stops. The tool is listed only where it can work, that is on the JVM build when a browser is found. The PHP build leaves it out: a PHP request cannot keep a browser between requests, and a capture loads the site's own preview pages, which a single-process PHP server could not answer while it waits.

`upload_theme_image` stages a theme-owned image. Review its preview and pass its ID, SHA-256 and measured dimensions to `verify_theme_image`. Use the resulting managed URL with `set_theme_block_image`. Theme-owned assets live in the theme storage and travel with its export.

### Theme design skill

Every connection that can read a theme serves the `haxepress-theme-design` [Agent Skill](https://agentskills.io/specification): the workflow for creating or restyling a theme, the document model, the edit operations and a review checklist for the preview tool. Its files live in `mcp/skills/haxepress-theme-design/` and are embedded in the build (`common.hxml`), so a client always gets the version that matches the site. Clients receive it in four ways:

- Hosts that support the [MCP skills extension](https://modelcontextprotocol.io/seps/2640-skills-extension) see `io.modelcontextprotocol/skills` in the server capabilities and discover the skill with `skills/list` and `skills/get`, which return its frontmatter and the SHA-256 digest and size of each file.
- Every file is a `text/markdown` resource under `skill://haxepress-theme-design/`, starting with `SKILL.md`. The server instructions point the model at it.
- `get_theme_design_skill` returns `SKILL.md` or a named reference file, for clients that only use tools.
- The `design_theme` prompt takes a brief and starts a conversation with the skill.

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

Run `python3 tests/run.py --only admin_mcp`, `python3 tests/run.py --only theme_mcp` and `python3 tests/run.py --only cms_lifecycle` after building the JVM; `python3 tests/php_application.py` connects an MCP link to the packaged PHP build. These suites cover bearer binding and revocation, standard SDK clients, native admin actions, verified content and theme uploads, browser tool permissions, live revisions and plugin registration.
