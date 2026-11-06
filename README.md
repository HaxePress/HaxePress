# HaxePress

> **Development preview — not production-ready.** HaxePress is under active development and is intended for local testing and evaluation. APIs, package compatibility and database schemas may change; it has not completed production security, reliability or performance validation.

HaxePress is a general-purpose content management system built with **HxWell**, its native ORM/Schema/Cache/Storage APIs, **hxwell-crossbyte** and **[Wellout](https://github.com/hxwell/wellout)**. The JVM renders the public site, themes, plugin pages and administration from type-checked Wellout templates (`*.well.html`). Browsers receive HTML; small client islands built with TypeScript and Vite add interactive parts such as the content editor and the theme builder. English is the default language; Turkish is included.

The current release is **2.16.0**, with **plugin/theme API 4**. The application runs on **JVM** with **SQLite or MySQL**. Native extension packages include JVM JAR, C++ CPPIA and PHP modules in one version-specific ZIP.

## Run locally

Install Git, Make, Python 3.12+, Java 21+, Maven, Node.js 22.12+ with npm, and Neko for the HxWell CLI. Install uv if you run the format checks. Setup uses Haxe 4.3.7 and installs the Haxe libraries and Git snapshots from `dependencies.lock.json` in the workspace. Maven resolves the JVM dependencies from `pom.xml` and copies the runtime JARs into `java-lib`. For development, set `HXWELL_PATH`, `HXWELL_CROSSBYTE_PATH` or `WELLOUT_PATH` to a compatible local checkout.

```sh
make setup
```

Setup uses HxWell's native `generate:key` command, the same key-generation process used by `hxwell new`, to initialize `APP_KEY` when needed. An existing `.env` and its nonempty key are preserved. The web installer keeps that key and updates only CMS settings. Direct connections from **127.0.0.1** automatically open the first-run wizard, even when `INSTALL_TRUSTED_IPS` is empty or invalid. To install from another address, explicitly allow its socket-peer IP:

```dotenv
INSTALL_TRUSTED_IPS=192.0.2.10,::1
```

Replace the example with the actual socket-peer addresses for your installation connection. Other addresses stay locked unless allowed; the exception is specifically `127.0.0.1`, not the entire loopback range or `::1`. Use a direct connection or an SSH tunnel; forwarded identity headers are rejected during installation.

```sh
make build
make run
```

Open [the installation wizard](http://127.0.0.1:3000/admin/install). Choose SQLite or MySQL, verify an empty writable database, set your site and administrator details, then finish. SQLite creates its file under the configured storage disk. MySQL requires an existing empty database and a user with schema permissions. Sample content is optional.

The wizard saves database settings and the chosen initial administrator password in `.env` with private file permissions, stores only a password hash in the database, and disables itself after completion. Keep the real `.env`, databases and `storage/` data outside Git. Existing installations with administrator records are detected and preserved. See [installation](docs/INSTALLATION.md).

After setup, open [the site](http://127.0.0.1:3000/) or [administration](http://127.0.0.1:3000/admin). Later administrator changes live in the database; changing the initial bootstrap variables does not reset existing accounts.

The framework's own CLI is available through the isolated project compiler:

```sh
python3 scripts/hxwell.py build jvm
python3 scripts/run.py
```

The launcher starts the JVM HTTP application, which renders every page itself; no Node.js process takes part in rendering. The JVM also manages the private Node.js MCP SDK host for admin and theme tools. Configure `HOST`, `PORT`, `MAX_CONNECTIONS`, `WORKERS`, `DB_PATH`, `STORAGE_PATH`, `CACHE_PATH` and `SESSION_PATH` in `.env`. The default database is `storage/cms.sqlite`. [MCP setup](docs/THEME-MCP.md)

## Definition-driven CMS

Owners create and configure collections at `/admin/collections`: stable keys, labels, public paths, named templates, editor features, validation constraints and custom fields. The same controllers, working copies, revisions, publication workflow, query builder and caches serve every collection. Types and fields can be changed without restarting the JVM.

Structured fields support short/long text, numbers, booleans, dates, choices and uploaded images. Explicit list columns use bounded SQL subqueries; public filters bind native membership queries. Public responses omit private fields, and incompatible values from a changed field definition are suppressed until edited. Values remain stored when a field is removed from the editor.

Roles and capability grants live in the database. Collections can use shared Content access or a dedicated permission; menus and server endpoints follow the same grants. Navigation regions are stored definitions, themes can declare additional regions, and managed links follow any public content item or collection. Reading settings select a collection or a published content item for the homepage.

Themes provide partial or additional named public templates with standard fallback views. Native plugins register owned collections, fields and capabilities and use the same query/storage contracts. See [the architecture and acceptance record](docs/DYNAMIC-CMS.md).

## Content management

- Create, edit, schedule, publish, feature, trash, restore and permanently delete content and pages.
- Organize content with database-backed categories and tags, search and cursor pagination.
- Use the Markdown/GFM editor, split preview, formatting tools, keyboard shortcuts and uploaded images.
- Keep private working copies, ordered autosaves, stale-save protection and the latest 50 revisions per item.
- Manage media descriptions, reusable image uploads and protection for referenced files.
- Configure site information, language and header/footer navigation.
- Manage owners, editors and writers, with server-side permissions and session revocation.
- Install, preview, configure and activate themes; preview desktop, tablet and mobile viewports in an isolated frame.
- Install version-specific native plugins with creation/destruction callbacks, route ownership, settings and lifecycle diagnostics.
- Schedule private site backups with per-rule sections, encryption and retention. [Backup and restore](docs/INSTALLATION.md#site-backups)
- Extend the data model with plugin-owned models/tables, named migrations, relationships, scoped JSON state and configured database connections.
- Share translations between the administration interface, themes and plugins.

RSS, Newsletter and JVM Backups ship as default plugins that can be deactivated. Reading Companion is an optional sample. Simple is the minimal default theme. Fieldnotes, Notebook and Gallery are independently packaged themes. Each package keeps its own identity and translations.

Published content uses `/content/{slug}`, the content index uses `/content`, pages use `/pages/{slug}` and tag archives use `/tags/{slug}`. Administration uses `/admin/content`, `/admin/pages`, `/admin/media`, `/admin/categories`, `/admin/tags`, `/admin/navigation`, `/admin/themes`, `/admin/plugins`, `/admin/team`, `/admin/activity` and `/admin/settings`.

## Native data architecture

`hx.press.model.ContentItem` stores content and pages in `content_items`; `content_type` references a stored content type; Content (`entry`) and Pages (`page`) are seeded defaults. `ContentTag` uses `content_tags.content_id`. Application services live in the `hx.press.*` namespace. Public pages are the Wellout views `Home`, `ContentIndex`, `ContentDetail`, `Page`, `About` and `NotFound`.

Queries select only the response's fields, filter/count/order in SQL and use bounded cursor pages. Content bodies are loaded for a specific detail/editor operation, search predicate or bounded migration. Reading time is write-time metadata. Query-specific caches include identifiers, filters, cursor and page size; native writes invalidate the affected domains. Cached values are typed plain records, not ORM instances.

Application and test code use native model/query builder and Schema APIs, without raw SQL. Necessary framework compatibility changes are reproduced by `patches/hxwell-query-builder.patch`; statement generation stays inside the framework. The patch includes safe grouped predicates, projections/subqueries, ordering, native/legacy SQLite upsert and model connection metadata preservation.

Application configuration also lives under `hx.press.config`. The `hxwell_config_package=hx.press.config` compiler define selects these configurations over the framework defaults. Setup reproduces this configurable discovery through `patches/hxwell-config-package.patch`; framework types retain their `hx.well.*` namespace.

Application/plugin/Haxe test file access uses `Storage` and configured disks. Media, extensions and exports have separate disks; archive extraction and CSV exports use bounded streams. Physical paths are resolved only at native runtime boundaries. The framework API, package loader and owner-managed code operate with the application's permissions.

## Extension authors

See [the API 4 package contract](docs/PLUGIN-PACKAGES.md) for native lifecycle, routes, storage, migrations, models, JSON state, themes and translations. `make build` generates the SDK and ZIP packages under `Export/packages/` and publishes download copies under `public/packages/`.

The source is organized as follows:

| Location | Purpose |
| --- | --- |
| `src/hx/press/` | Application services, controllers and content queries |
| `src/hx/press/database/` | Schema, bounded migrations and query metadata |
| `src/hx/press/plugins/` | Native loaders, lifecycle, plugin database APIs |
| `src/hx/press/packages/` | ZIP inspection, installation, settings and themes |
| `src/hx/press/routes/` | Route groups and legacy URL redirects |
| `src/hx/press/i18n/` | Request-local translation catalogues |
| `src/hx/press/model/` | Typed core ORM models |
| `src/hx/press/config/` | Application configuration and provider registration |
| `src/hx/press/handler/` | Public and guarded administration handlers |
| `resources/views/` | Wellout pages, layouts and components |
| `resources/js/` | Client islands, the theme builder and the content editor |
| `resources/css/` | Scoped site and administration styles |
| `examples/` | Native plugin and theme sources |
| `tests/` | Isolated JVM/CPPIA/PHP checks and ORM fixtures |

## Upgrading an existing installation

Back up `.env`, the database and managed `storage/` data before upgrading. The legacy naming migration renames the old content/tag tables and reference column through Schema APIs, preserves IDs/content/relationships, normalizes the old content type, working-copy keys and revision snapshots, and updates factory defaults only when they still match the original values. Existing custom site text is retained. The structure migration replaces the global slug constraint with `(content_type, slug)`, renames menu references to `content_id`, and adds registry/value/grant tables. Old public URLs redirect to canonical routes.

Bundled older packages are replaced with API 4 builds while retaining settings, activation and the selected theme. Third-party native plugins must be rebuilt for the exact CMS 2.16.0 / API 4 release. Themes provide Wellout views; packages that only contain a JavaScript renderer are rejected. The SDK includes the shared `ValidationResponder` interface for native handler validation failures. Detail and page templates receive `item`; custom templates include a standard `templateFallback`. Plugin-owned data and migration histories remain in place. Keep custom `DB_PATH` values; the local project's original default filename is migrated to `storage/cms.sqlite` during deployment.

## Verification

```sh
make test
make test-cppia
make test-php
PATH="$PWD/.tools/haxe:$PATH" npm run format:check
```

The [CI workflow](.github/workflows/ci.yml) runs setup, formatting, the application and extension build, and the JVM integration suite on Ubuntu for pushes and pull requests to `main`. It uses Haxe 4.3.7 and Java 21.

The JVM suite uses temporary databases, actual Crossbyte processes and a test-only ORM fixture process. It exercises permissions, uploads, caches/projections, cursor pagination, revision/scheduling flows, package replacement, migrations and languages. Native C++ and PHP hosts load real extension modules and run the same persistence contract checks. An existing-installation rehearsal verifies preserved data, relationships, working copies, revision snapshots, package state, redirects and repeat startup.

[The acceptance record](docs/CMS.md) describes the current verification evidence. Historical API 2 records are retained under `docs/history/`.

Media deletion enforces live content, plugin and database relationships. See [the dependency contract](docs/MEDIA-DEPENDENCIES.md) for persistent references, watched model columns and lifecycle behavior.

Site identity accepts PNG, JPEG and GIF logo uploads and supports theme-font text fallback and generic publisher/site descriptions. See [site identity](docs/SITE-IDENTITY.md) for settings, upload validation and legacy-value migration.

Theme cards show live miniature previews. Simple is an application-owned default with bundled styles and catalogues, and cannot be uninstalled or replaced by an uploaded package. See [themes](docs/THEMES.md).

**Themes → Create theme** opens the nested layout builder, with Flexbox/Grid, responsive and interaction styles, reusable components, custom templates, HTML/CSS import, query-backed repeaters, managed images and separate draft/publish actions. See [the visual theme builder](docs/THEME-BUILDER.md).

WebSocket cleanup is covered by shared Crossbyte and Undertow transport regressions. See [session lifecycle](docs/WEBSOCKET-LIFECYCLE.md).

Theme editor uploads belong to the theme, use a separate Storage disk, and travel with visual-theme exports. See [theme images](docs/THEME-ASSETS.md).

Pages are written in Wellout, a type-checked server-side template language developed in its own repository. See [the template language integration](docs/TEMPLATE-LANGUAGE.md) and [the porting guide](docs/WELLOUT-PORTING.md).
