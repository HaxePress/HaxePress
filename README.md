# HaxePress

> **Development preview — not production-ready.** HaxePress is under active development and is intended for local testing and evaluation. APIs, package compatibility and database schemas may change; it has not completed production security, reliability or performance validation.

HaxePress is a general-purpose content management system built with **HxWell**, its native ORM/Schema/Cache/Storage APIs, **hxwell-crossbyte** and **[Wellout](https://github.com/HaxePress/WellOut)**. The JVM renders the public site, themes, plugin pages and administration from type-checked Wellout templates (`*.well.html`). Browsers receive HTML; small client islands built with TypeScript and Vite add interactive parts such as the content editor and the theme builder. English is the default language; Turkish is included.

The current release is **2.16.0**, with **plugin/theme API 4**. The application runs on **JVM** or **PHP** with **SQLite or MySQL**. Native extension packages include JVM JAR, C++ CPPIA and PHP modules in one version-specific ZIP.

## Run locally

Install Git, Make, Python 3.12+, Java 21+, Maven, Node.js 22.12+ with npm (to build the front-end assets and run the tests; the site itself runs without Node.js), and Neko for the HxWell CLI. Install uv if you run the format checks. Setup uses Haxe 4.3.7 and installs the Haxe libraries and Git snapshots from `dependencies.lock.json` in the workspace. Maven resolves the JVM dependencies from `pom.xml` and copies the runtime JARs into `java-lib`. For development, set `HXWELL_PATH`, `HXWELL_CROSSBYTE_PATH` or `WELLOUT_PATH` to a compatible local checkout.

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

Open [the installation wizard](http://127.0.0.1:3000/admin/install). Choose SQLite or MySQL, verify an empty writable database, set your site and administrator details, then finish. SQLite creates its file in `private/database` (`DATA_PATH`), apart from the uploaded files and caches in `private/storage`. MySQL requires an existing empty database and a user with schema permissions. Sample content is optional.

The wizard saves the database settings in `.env` with private file permissions, creates the administrator in the database with only a hash of the password, and disables itself after completion. `.env` keeps no administrator credentials; startup clears any that earlier versions left there. Keep the real `.env` and the `private/database` and `private/storage` folders outside Git. Existing installations with administrator records are detected and preserved. From a proxy or a Cloudflare Tunnel, setup opens with the setup key that HaxePress prints when it starts and keeps in `.env` as `INSTALL_KEY` until installation finishes. See [installation](docs/INSTALLATION.md).

After setup, open [the site](http://127.0.0.1:3000/) or [administration](http://127.0.0.1:3000/admin). Later administrator changes live in the database; changing the initial bootstrap variables does not reset existing accounts.

The framework's own CLI is available through the isolated project compiler:

```sh
python3 scripts/hxwell.py build jvm
python3 scripts/run.py
```

The launcher starts the JVM HTTP application, which renders every page and serves the site's MCP server (admin and theme tools) itself; no Node.js process runs with the site. Configure `HOST`, `PORT`, `MAX_CONNECTIONS`, `WORKERS`, `DB_PATH`, `DATA_PATH`, `STORAGE_PATH`, `CACHE_PATH` and `SESSION_PATH` in `.env`. Only `public/` is served over HTTP; everything else the site keeps is under `private/`. The default database is `private/database/cms.sqlite`, `private/storage` holds uploaded files, installed plugins and themes, caches and sessions, `private/packages` the plugin and theme archives shipped with the build (`PACKAGES_PATH`), and `private/seeds` the sample content. [MCP setup](docs/THEME-MCP.md)

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

RSS, Newsletter, Cloudflare, View Count and JVM Backups ship as default plugins that can be deactivated. Cloudflare takes each visitor's address from `CF-Connecting-IP` and country from `CF-IPCountry`, but only on connections from Cloudflare's published edge ranges, or from this server when its Cloudflare Tunnel setting is on, so other visitors cannot choose the address that sign-in limits see or the country they are counted in. View Count counts visitors' views of published content for its administration page, the dashboard, JSON data and an MCP tool, and can show them on content pages. A setting, off by default, also counts them per visitor country, which only the Cloudflare plugin provides; without it a view counts as `UNKNOWN`. A page view writes nothing to the database: the plugin's middleware decides what a view is and keeps the counts in memory (PHP: in a file of the minute), and its job writes them once a minute. The application only tells plugins which published item a page shows, the visitor's trusted country and whether a member is signed in, so another plugin can count visits its own way. [Content views](docs/PLUGIN-PACKAGES.md#content-views) Content lists let each member choose, order and sort their columns, and plugins add columns of their own with `ContentColumns`, as View Count does with **Views**. [Content list columns](docs/PLUGIN-PACKAGES.md#content-list-columns) Reading Companion is an optional sample that updates replace once it is installed. Simple is the minimal default theme. Fieldnotes, Notebook and Gallery are bundled themes: they are always installed, every update replaces them with its own build while keeping their settings and activation, and they cannot be removed or replaced by an upload. Each package keeps its own identity and translations.

Published content uses `/content/{slug}`, the content index uses `/content`, pages use `/pages/{slug}` and tag archives use `/tags/{slug}`. Administration uses `/admin/content`, `/admin/pages`, `/admin/media`, `/admin/categories`, `/admin/tags`, `/admin/navigation`, `/admin/themes`, `/admin/plugins`, `/admin/team`, `/admin/activity` and `/admin/settings`.

## Native data architecture

`hx.press.model.ContentItem` stores content and pages in `content_items`; `content_type` references a stored content type; Content (`entry`) and Pages (`page`) are seeded defaults. `ContentTag` uses `content_tags.content_id`. Application services live in the `hx.press.*` namespace. Public pages are the Wellout views `Home`, `ContentIndex`, `ContentDetail`, `Page`, `About` and `NotFound`.

Queries select only the response's fields, filter/count/order in SQL and use bounded cursor pages. Content bodies are loaded for a specific detail/editor operation, search predicate or bounded migration. Reading time is write-time metadata. Query-specific caches include identifiers, filters, cursor and page size; native writes invalidate the affected domains. Cached values are typed plain records, not ORM instances.

Application and test code use native model/query builder and Schema APIs, without raw SQL. Necessary framework compatibility changes are reproduced by `patches/hxwell-query-builder.patch`; statement generation stays inside the framework. The patch includes safe grouped predicates, projections/subqueries, ordering, native/legacy SQLite upsert, keyed counter increments (`upsertIncrement`) and model connection metadata preservation. `patches/hxwell-storage-append.patch` makes `Storage.append` one append-mode write, so concurrent PHP processes keep every line.

Application configuration also lives under `hx.press.config`. The `hxwell_config_package=hx.press.config` compiler define selects these configurations over the framework defaults. Setup reproduces this configurable discovery through `patches/hxwell-config-package.patch`; framework types retain their `hx.well.*` namespace.

Application/plugin/Haxe test file access uses `Storage` and configured disks. Media, extensions and exports have separate disks; archive extraction and CSV exports use bounded streams. Physical paths are resolved only at native runtime boundaries. The framework API, package loader and owner-managed code operate with the application's permissions.

## Extension authors

See [the API 4 package contract](docs/PLUGIN-PACKAGES.md) for native lifecycle, routes, storage, migrations, models, JSON state, themes and translations. `make build` generates the SDK and ZIP packages under `Export/packages/` and copies them to `private/packages/`, where the application installs them from; nothing serves them over HTTP.

The source is organized as follows:

| Location                 | Purpose                                                  |
| ------------------------ | -------------------------------------------------------- |
| `src/hx/press/`          | Application services, controllers and content queries    |
| `src/hx/press/database/` | Schema, bounded migrations and query metadata            |
| `src/hx/press/plugins/`  | Native loaders, lifecycle, plugin database APIs          |
| `src/hx/press/packages/` | ZIP inspection, installation, settings and themes        |
| `src/hx/press/routes/`   | Route groups and legacy URL redirects                    |
| `src/hx/press/i18n/`     | Request-local translation catalogues                     |
| `src/hx/press/model/`    | Typed core ORM models                                    |
| `src/hx/press/config/`   | Application configuration and provider registration      |
| `src/hx/press/handler/`  | Public and guarded administration handlers               |
| `resources/views/`       | Wellout pages, layouts and components                    |
| `resources/js/`          | Client islands, the theme builder and the content editor |
| `resources/css/`         | Scoped site and administration styles                    |
| `examples/`              | Native plugin and theme sources                          |
| `tests/`                 | Isolated JVM/CPPIA/PHP checks and ORM fixtures           |

## Run on PHP

`make build` also builds the application for PHP into `Export/php` (`python3 scripts/hxwell.py build php --hxml=php.hxml`). `global.hxml` (JVM, with the Crossbyte server) and `php.hxml` share `common.hxml`; on PHP, HxWell's PHP driver serves each request through `public/index.php`. The PHP build also includes the types PHP plugins link to (`plugin-host.hxml`). To try it, put a `.env` beside `hxwell.boot.php`, then serve `public/` from that folder:

```sh
cd Export/php/public
php -S 127.0.0.1:3010 index.php
```

PHP starts the application for each request, so the PHP build:

- runs migrations once per build and records it in the database;
- keeps compiled Wellout templates in `private/storage/cache/views` with Wellout's `PhpTemplateStore`, as PHP files that opcache serves; each file returns the template's operation tree as a PHP array, never code from a template, and output is still escaped by the same renderer;
- writes output with native PHP string functions;
- runs due scheduled tasks after responses and from `php hxwell.boot.php schedule:run`, which cron can call every minute;
- sends errors to PHP's error log.

The MCP server is the same Haxe code on both builds and keeps no state between requests, so PHP serves it too. PHP has no WebSockets: the admin pages and the theme editor post their MCP messages over HTTP and poll for changes instead of receiving them live, and the `preview_theme_design` tool, which drives headless Chrome, needs the JVM build. `python3 tests/php_application.py` checks the packaged PHP build, including an MCP link.

## Releases

Publishing a release on GitHub runs the Release workflow (`.github/workflows/release.yml`). It builds the release's tag with `make build`, packages it with `scripts/release.py`, starts the packaged application to check that it serves the installer, and attaches the files to the release. Those files are:

- `haxepress-<version>-jvm.zip`, the application for Java 21+, with `start.sh`, which creates `.env` with a new `APP_KEY` on first run;
- `haxepress-<version>-php.zip`, the application for PHP 8.1+, with `setup.php`, which creates `.env` with a new `APP_KEY`, and a README for web servers and cron.

Nothing else is attached. The plugins and themes of that build, where each plugin contains its JVM, CPPIA and PHP builds, are inside both archives in `private/packages` and install from the administration panel.

The workflow checks that each installation of either archive creates its own private `APP_KEY` (`tests/release_keys.py`) and serves both packaged applications before it attaches them. The release tag names the download; the CMS and plugin API versions inside come from `cms.json`. To rebuild a release's files, run the workflow by hand with its tag.

## Upgrading an existing installation

Back up `.env`, `private/database` and `private/storage` before upgrading; a release archive holds neither, so unpacking it over the site replaces the application and keeps the site's data. The legacy naming migration renames the old content/tag tables and reference column through Schema APIs, preserves IDs/content/relationships, normalizes the old content type, working-copy keys and revision snapshots, and updates factory defaults only when they still match the original values. Existing custom site text is retained. The structure migration replaces the global slug constraint with `(content_type, slug)`, renames menu references to `content_id`, and adds registry/value/grant tables. Old public URLs redirect to canonical routes.

Bundled older packages are replaced with API 4 builds while retaining settings, activation and the selected theme. Bundled themes and the Reading Companion sample are also replaced whenever the archive shipped with a release differs from the one they were installed from, even when the version number is the same; a removed bundled theme is installed again. Templates escape everything printed with `{{ }}`; print icons, rendered Markdown and other HTML helpers with `{!! !!}`. A third-party theme written for 0.0.1 that prints them with `{{ }}` shows their markup as text until it is updated. Third-party native plugins must be rebuilt for the exact CMS 2.16.0 / API 4 release. Themes provide Wellout views. Browser renderer themes are no longer supported: they are rejected on upload and removed on startup, and the shipped example themes are replaced with their Wellout builds. The SDK includes the shared `ValidationResponder` interface for native handler validation failures. Detail and page templates receive `item`; custom templates include a standard `templateFallback`. Plugin-owned data and migration histories remain in place. PHP sites before this release stored plugin and theme settings in a form they could not read back, so saved settings did not take effect; this release reads that form and writes plain objects, so those saved settings apply after the upgrade. Keep custom `DB_PATH` values.

## Verification

```sh
make test
make test-cppia
make test-php
PATH="$PWD/.tools/haxe:$PATH" npm run format:check
```

The [CI workflow](.github/workflows/ci.yml) runs setup, formatting, the application and extension build, the packaged PHP application check and the JVM integration suite on Ubuntu for pushes and pull requests to `main`. It uses Haxe 4.3.7 and Java 21.

The JVM suite uses temporary databases, actual Crossbyte processes and a test-only ORM fixture process. It exercises permissions, uploads, caches/projections, cursor pagination, revision/scheduling flows, package replacement, migrations and languages. Native C++ and PHP hosts load real extension modules and run the same persistence contract checks. An existing-installation rehearsal verifies preserved data, relationships, working copies, revision snapshots, package state, redirects and repeat startup.

[The acceptance record](docs/CMS.md) describes the current verification evidence. Historical API 2 records are retained under `docs/history/`.

Media deletion enforces live content, plugin and database relationships. See [the dependency contract](docs/MEDIA-DEPENDENCIES.md) for persistent references, watched model columns and lifecycle behavior.

A site publishes in one language until more are added on the Languages page. Other languages are served under their code, such as `/de/`, and can be disabled while they are prepared. Each translation of an item is its own item; an item can also be shown in every language until it is translated, and a page links its other languages for visitors and search engines. See [languages](docs/LANGUAGES.md).

The Translations page lists every text of HaxePress, the themes, the plugins and the site, in each site language: the translations packages ship, the ones made on the site, which win, and the texts still missing. Each member also chooses their own administration language. See [translations](docs/TRANSLATIONS.md).

Site identity accepts PNG, JPEG and GIF logo uploads and supports theme-font text fallback and generic publisher/site descriptions. See [site identity](docs/SITE-IDENTITY.md) for settings, upload validation and legacy-value migration.

Theme cards show live miniature previews. Simple is an application-owned default with bundled styles and catalogues, and cannot be uninstalled or replaced by an uploaded package. See [themes](docs/THEMES.md).

**Fork** on a theme card copies any theme into a new, inactive theme that belongs to the site and that updates leave as it is. A packaged theme's copy keeps its files and settings, and the built-in Simple theme's copy carries the application pages it renders; **Download** gives the copy's files as a ZIP, which installs as an update of the copy after you change it. A visual design's copy keeps its draft, its published version and its images and opens in the editor. Fork a bundled theme to change it.

**Themes → Create theme** opens the nested layout builder, with Flexbox/Grid, responsive and interaction styles, reusable components, custom templates, HTML/CSS import, query-backed repeaters, managed images and separate draft/publish actions. See [the visual theme builder](docs/THEME-BUILDER.md).

WebSocket cleanup is covered by shared Crossbyte and Undertow transport regressions. See [session lifecycle](docs/WEBSOCKET-LIFECYCLE.md).

Theme editor uploads belong to the theme, use a separate Storage disk, and travel with visual-theme exports. See [theme images](docs/THEME-ASSETS.md).

Pages are written in Wellout, a type-checked server-side template language developed in its own repository. See [the template language integration](docs/TEMPLATE-LANGUAGE.md) and [the porting guide](docs/WELLOUT-PORTING.md).
