# CMS implementation and acceptance

The existing HxWell/JVM, SQLite, Crossbyte and Inertia application becomes an English-language CMS. Existing content, uploaded files and administrator credentials must survive the upgrade. Application and test code continue to use Eloquent/query builder and Schema APIs without hand-written SQL.

## Required capabilities

- [x] Database-backed tags, inline assignment, public tag archives and bounded tag search.
- [x] Separate story and page collections, reusable editor and public page routes.
- [x] Draft, published, scheduled and trash workflows, restore and permanent deletion.
- [x] Editor toolbar, split preview, keyboard commands, word count, server working copies, revision history and restore, SEO fields and media selection.
- [x] Media library with upload, metadata editing, bounded search/pagination and protection for files referenced by content.
- [x] Theme registry, three distinct bundled themes, activation, customization and preview. Theme selection must affect the public site and persist across restarts.
- [x] Panel upload and installation of ZIP plugin packages, with a manifest, both JAR/CPPIA server modules for an exact CMS release and optional frontend assets. Extensible hooks, native creation/destruction methods, activation/deactivation, settings, replacement/update and uninstall lifecycle; include working example packages. Disabled plugins must stop affecting public output.
- [x] Editable header/footer navigation using published pages and safe links.
- [x] Team management and explicit administrator capabilities, retaining the admin guard and admin-only sessions.
- [x] Activity records and useful CMS dashboard summaries.
- [x] Query-specific caches, SQL filtering/counting/ordering and bounded cursor lists for all new collections.
- [x] Upgrade and fresh-install tests, CMS mutation/cache tests, scheduling and revision tests, and preservation checks using ORM fixtures.
- [x] Production JVM excludes test helpers. Frontend type checking, Vite/SSR builds, JVM build and source formatting pass.
- [x] Browser review of the full admin workflows, all themes, editor and public archives at desktop and mobile widths.

## Design direction

Continue Fieldnotes' established editorial identity. The studio uses white surfaces, quiet olive navigation and the existing sans-serif controls; content remains the dominant element. Group navigation by content, organization, appearance and administration. New forms use clear sentence-case labels and specific empty states. Theme previews must show actual published content.

The bundled public themes will be Fieldnotes (the current spacious journal), Notebook (a cooler, compact editorial layout) and Gallery (an image-led publication). Each theme has its own typography, spacing and layout as well as color settings. Theme/plugin code stays separate from editorial data.

## Verification ledger

Completion is unproven until every requirement above is implemented and verified against the current source, test results and rendered application. Record the tests and any remaining work here as implementation proceeds; do not treat a catalog screen or a configuration toggle alone as a working theme/plugin system.

### Verified implementation

- `python3 tests/run.py` passed against the final source: the original 17 HTTP checks, scoped-query/cache checks, transaction and ZIP inspection checks, tags, package lifecycle, content/editor/media workflows, team/navigation permissions, restart persistence and multi-batch migrations.
- Package tests execute the real Haxe JVM example, replace it with newly compiled code under the same entrypoint name, preserve settings, reject invalid archives, encrypt private settings, and verify disabled hooks/assets and uninstall cleanup. All three themes activate, customize and preview actual content.
- Content tests cover separate pages, GFM/escaped HTML, exact custom SEO titles, private ordered working copies, consumed draft keys, stale-save conflicts, revision preview/restore, due publication, trash/restore and protection for images referenced by revisions or working copies.
- Management tests cover owner/editor/writer capabilities, author-scoped lists and dashboard data, live role changes, deactivation, password-based session revocation, last-owner protection, safe menus, page slug/status changes and activity filtering.
- Larger ORM fixture checks verify independent expected counts and forward/back cursors, including tied/null dates. A native result-set guard rejects article bodies on list paths and extra/unrequested detail rows. Cold queries, warm caches, expiration and concurrent fills are exercised separately.
- `make build`, `npm run format:check` and production JAR inspection passed. No fixture or query-guard classes are present in the production JVM artifact. Application/test source scans found no raw SQL or executable qualified Haxe type references. The Inertia compatibility patch reverses and reapplies cleanly, including its formatted JVM transport.

### Browser review

The isolated review database was separate from the user's content. The review covered desktop (1280 px) and mobile (390 px) layouts, with no document-width overflow on the checked screens.

- Created a tag and page through the panel; assigned tags, selected a stored cover, entered SEO fields and published the page.
- Rendered GFM tables/tasks in split preview; uploaded an inline image; reloaded the editor and recovered its private working copy; saved a second revision, previewed the first and restored it as a working copy without changing live content.
- Edited media metadata, added a managed page link and followed it from the mobile public menu.
- Previewed and activated Gallery, Notebook and Fieldnotes; checked their distinct desktop/mobile layouts and confirmed previews include the managed menu.
- Uploaded, inspected, installed and activated Reading Companion using the panel's ZIP controls. The browser module created an accessible reading-progress bar and reached 100% on scroll. Deactivation followed by Inertia navigation removed the bar and its public contribution.
- Reviewed team, account, activity and mobile editor layouts. The final mobile studio includes its sign-out control. Public tag archives displayed the newly published tagged story. Browser console inspection found no errors in the final review tab.
- Review images are saved locally under `outputs/cms-editor-desktop.jpg`, `outputs/cms-editor-mobile.jpg` and `outputs/cms-tag-mobile.jpg`.

### Existing installation upgrade

Before switching the local preview, a private backup was created at `storage/backups/pre-cms-20261103-215239/`. The actual database and media were copied into an isolated upgrade rehearsal. ORM comparisons preserved all original article fields, categories, account names/emails/password hashes, subscribers and existing setting values. File hashes matched before and after. The eight articles, five categories, one administrator, one subscriber and seven managed images survived; three bundled themes were installed. A non-image `.gitkeep` was preserved and correctly excluded from the media catalog.

The main preview was then restarted with the production JVM and current SSR bundles. Its public Inertia response returns eight published stories, the Fieldnotes theme and managed navigation without creating a session. Detailed local verification output is in `outputs/cms-upgrade-verification.json`; it contains counts and paths, not credentials.

### Runtime compatibility notes

The project-local JDBC patch restores auto-commit after commit/rollback. A regression test reproduces the ordinary-write loss without it and passes with it. Setup reapplies the patch idempotently. Admin session changes are saved before sending a redirect, using the native session API; public routes remain session-free.

Crossbyte's default per-address request quota remains active in production. Functional test builds omit that outer quota because the combined suite sends hundreds of requests from one loopback address. The application's separate login-attempt throttle remains active in tests and production. This resolved earlier aggregate-suite HTTP 429 failures without adding retries or weakening assertions.

### JAR and CPPIA plugin backends

The plugin module facade selects a JVM/JAR or native C++/CPPIA backend at compile time. Plugin ZIPs require both `server.jar` and `server.cppia` with a shared entrypoint name and exact `cmsVersion`. RSS, Newsletter and Reading Companion are built for both targets from the same source. API 2 defines native `onCreate(host, context)` and `onDestroy()` methods alongside JSON event dispatch. The source SDK exports the shared interfaces for CPPIA compilation.

Native C++ tests verify CPPIA hook calls, content validation, replacement, module isolation, close behavior, interface rejection and streamed ZIP validation. Both known-size ZIP entries and data descriptors are covered. JVM integration tests retain the JAR lifecycle and validate the new inspection metadata. The production CMS remains a JVM application; the separate native host verifies the C++ plugin subsystem.

### Native plugin lifecycle and feature extraction, 2026-11-04

- `onCreate(host, context)` and `onDestroy()` execute on real JAR/CPPIA instances. Native route changes are batched, owned routes are removed on stop, and plugin admin routes reuse the existing session, CSRF and administrator middleware.
- Creation/destruction failures disable the package, retain its error and restart flag on its card, and show a studio-wide warning until process restart. Uninstalling a failed package preserves the process warning. Tests cover creation rollback, destruction cleanup, protected routes, route-name reuse and blocked reactivation before restart.
- RSS Feed and Newsletter now own their routes, queries, handlers, navigation, dashboard contribution and browser assets. Deactivation removes these contributions and retains subscriber data. Bundled installation runs once, and the existing newsletter heading moves into plugin settings.
- Every plugin ZIP requires both JAR and CPPIA artifacts, API 2 and an exact `cmsVersion`. Upload tests reject missing declarations/files, missing versions, incompatible releases and version ranges. All three bundled plugin ZIPs were inspected after the production build.
- The final `python3 tests/run.py`, `make build` and `npm run format:check` passed. The JVM suite also checks graceful shutdown with multiple running plugins, preserving the module registry while each instance is destroyed. Results are in `outputs/lifecycle-full.log`, `outputs/lifecycle-build.log` and `outputs/lifecycle-format-check.log`.
- Native C++/CPPIA tests passed with both ZIP encoding variants. They load the real RSS/Newsletter modules, register/remove their native routes, create the subscriber schema through HxWell and query/render the feed. Results are in `outputs/lifecycle-cppia.log`. This verifies the native plugin host; the deployed CMS continues to run on JVM.
- The existing-installation rehearsal and live upgrade preserved all eight articles, five categories, the administrator account and credentials, the subscriber, existing settings/themes and media files. Backup: `storage/backups/pre-plugin-lifecycle-20261104-000133/`. Seven managed images and their `.gitkeep` were preserved. The production preview at port 3000 now runs the new JVM build with RSS and Newsletter active. Read-only HTTP checks verified the public feed, plugin panel and subscriber panel; ORM comparisons used private database copies. Counts and results are in `outputs/lifecycle-upgrade-verification.json`.

The earlier browser review above belongs to the original CMS implementation. This lifecycle update was verified through HTTP, rendered HTML, JVM integration tests and the native C++ host; its new browser form was not separately exercised in an interactive browser.

### Shared translations, 2026-11-04

Core, plugin and theme translations use a common Haxe/React contract. English remains the initial default and fallback. The core contains 699 matching English/Turkish message keys, including plain messages, named placeholders, one/other plural forms and localized date labels. Public/studio language selectors store a separate preference cookie without opening a public session; owners configure the default language in Settings. Locale is request-local and does not modify the JVM's global locale.

Plugin/theme manifests declare validated JSON catalogue paths. Namespaces follow package identity, catalogue cache keys include installed generation and locale, and metadata queries select only three needed columns with bounded SQL results. Active themes can override public labels; inactive previews and package settings use the requested package's catalogues. Browser modules receive `locale` and a package-bound `t` function. Native JAR and CPPIA modules call the same `I18n.t` service. Existing bundled packages receive their catalogues through an idempotent upgrade that preserves settings and activation.

- The full JVM integration suite passed, including concurrent English/Turkish SSR, document language/headers, session-free preferences, native plugin errors, namespace isolation, English fallback, placeholders/plurals, malformed catalogue rejection, replacement invalidation, theme preview and unchanged editorial content. Results: `outputs/i18n-full.log`.
- A final targeted translation run also verifies that a 31-row subscriber list uses its plugin namespace in translated pagination. Results: `outputs/i18n-integration.log`.
- `make build` and `npm run format:check` passed. Production JAR inspection excludes fixture/query-guard classes. Source scans found no raw SQL or executable qualified Haxe type calls. Setup reproduced the current local framework patches, including SSR root-template access to page props.
- Native C++ tests passed for both archive encodings. A real CPPIA Newsletter module reads its installed catalogue through the shared service and returns translated navigation. Core UTF-8 messages and plurals are also checked. Results: `outputs/i18n-cppia.log`.
- The private upgrade rehearsal and live JVM checks preserved eight stories, five categories, one administrator and its credentials, one subscriber, seven managed images, six menu links, existing settings, and package settings/activation. Backup: `storage/backups/pre-i18n-20261104-005830/`. English remains the live default; Turkish SSR, studio pages and native newsletter responses were checked over HTTP. Results: `outputs/i18n-upgrade-verification.json`.

This update was verified through rendered HTTP responses and integration tests. The language selector was not separately exercised through interactive browser automation.

### Simple default and standalone editorial themes, 2026-11-04

Simple is now the default public theme: white background, system typography, one reading column and plain article lists. The original Fieldnotes pages and styles moved into `examples/themes/fieldnotes/`. Its installable ZIP includes the actual React renderer, fonts, image and translations. Notebook and Gallery also ship complete renderer artifacts. The studio retains its existing interface.

Theme modules receive the application's React/Inertia runtime. The browser and SSR worker load the same installed module; matching Suspense boundaries preserve hydration. The build rejects an accidentally embedded React runtime. Shared application CSS now contains UI/admin foundations and Markdown styling, while editorial presentation belongs to the theme package.

- The full JVM suite passed with Simple as the fresh-install default. Package tests activate all four themes and check their actual SSR markup, renderer asset serving, previews and customization. Existing CMS, upload, authorization, query/cache, language and migration checks passed. Results: `outputs/themes-full-test.log`.
- `make build`, native C++/CPPIA checks and `npm run format:check` passed. Fieldnotes ZIP inspection confirms its renderer, stylesheet, bundled fonts/image, source and catalogues, with no embedded React runtime. Results: `outputs/themes-build.log`, `outputs/themes-cppia.log` and `outputs/themes-format-check.log`.
- A fresh, temporary Chromium profile reviewed Simple and packaged Fieldnotes at 1280 px and 390 px. Both have no document-width overflow. Browser navigation through the journal and an article retained each theme, loaded article covers and produced no console/runtime errors. Screenshots and results: `outputs/theme-simple-*.png`, `outputs/theme-simple.json`, `outputs/theme-fieldnotes-package-*.png` and `outputs/theme-fieldnotes-package.json`.
- The actual database was backed up at `storage/backups/pre-simple-theme-20261104-015310/`. Rehearsal and live ORM comparisons preserved eight stories, five categories, the administrator and credentials, the subscriber, seven managed images, six menu links, existing settings and package configuration. Plugin activation was preserved. Simple was selected intentionally, and Fieldnotes remains installed with a working owner preview. Evidence: `outputs/simple-theme-upgrade-verification.json`.
- The live JVM at port 3000 was checked again in Chromium at desktop/mobile widths, including journal/article navigation and a clean console. English remains the default, and Turkish SSR still works. Evidence: `outputs/theme-simple-live.json`.

### Isolated theme-preview toolbar, 2026-11-04

Theme preview now renders `Admin/ThemePreview` as an outer toolbar page with a dedicated iframe. Only the iframe loads the candidate's renderer, stylesheet and assets. Theme layouts no longer own the toolbar, and legacy renderer bundles receive a suppressed inline-preview flag. Protected frame routes support the homepage, journal, stories, pages, tags and author page; contextual links and GET forms retain the selected theme and locale without activating it.

The parent page retains `X-Frame-Options: DENY`. Only registered preview-content routes receive `SAMEORIGIN` and `frame-ancestors 'self'`. Both parent and frame retain the administrator route-group guard and owner capability checks.

- The full JVM integration suite, production build and formatting checks passed. Tests verify the separate shell/content responses, frame headers, owner-only access, absence of theme assets in the parent, absence of duplicate toolbars, preview navigation and retained active-theme selection. Results: `outputs/preview-frame-full-test.log`, `outputs/preview-frame-build.log` and `outputs/preview-frame-format-check.log`.
- Fresh-profile Chromium checks at 1280 px and 390 px found one outer toolbar, no toolbar inside the frame, no theme stylesheets in the parent and no overflow. Injecting aggressive CSS into the iframe did not change the parent toolbar's height or color. Journal navigation stayed inside the candidate theme, and the console remained clean. Evidence: `outputs/theme-preview-frame-browser.json` and `outputs/theme-preview-frame-*.png`.
- The local JVM was updated and bundled editorial renderer packages were refreshed while retaining settings. A private backup is stored at `storage/backups/pre-preview-frame-20261104-032235/`. The pre-update Simple selection was restored; editorial content, credentials, subscriptions, menus and image files were retained. Production's normal address quota was reached by the repeated browser probe, so the complete browser-flow verification above uses the isolated review server.

### Preview viewport controls, 2026-11-04

The isolated preview toolbar now offers Desktop (available width), Tablet (768 px) and Mobile (390 px). Constrained viewports are centered on a neutral canvas. Changing the selection resizes the existing iframe, preserving its document and current navigation. Controls use translated labels and accessible pressed states.

Type checking, production JVM/SSR builds and formatting checks passed. Fresh-profile Chromium checks verified exact iframe widths, one selected control, document preservation during resizing, retained mobile selection after journal navigation, a 390 px host without toolbar overflow, and English/Turkish labels with a clean console. Evidence: `outputs/preview-devices-browser.json` and `outputs/preview-device-*.png`. The updated local JVM also passed live checks for the controls and translated labels.

### Native Storage API migration, 2026-11-04

Application, plugin and Haxe test file operations now use `hx.well.facades.Storage`. The project-local framework copy includes the new API. `StorageConfig` extends the framework's filesystem configuration and registers application disks through `Config.set`: existing storage/media/extensions/export paths are retained, while public assets and seed files use read-only disks.

Media saves use native atomic `put`, quarantine/delete uses `move`/`delete`, and media/package responses use Storage streams. Package extraction feeds bounded entry Inputs into `writeStream` on JVM and C++; size, count, CRC and path validation remain active. Package directory installation moves inspected, bounded file trees through the disk API. Legacy staged-upload paths remain accepted. Translation files, seed data and CPPIA bytecode are read through Storage. JVM archive/class-loading boundaries obtain physical paths through `Storage.path()`.

Newsletter CSV generation produces 100-row ORM batches through an Input into `Storage.writeStream`, then returns `Storage.download`. A stream-close decorator deletes the temporary file after completion or disconnect. The plugin SDK exports Storage for both server targets. Node's SSR module import and build/deployment tools retain their language-native runtime/tooling interfaces.

- The full JVM suite passed, including cold/warm cache guards, image uploads, managed-image migrations, streamed exports, package install/replacement/uninstall, archive expansion checks, theme previews, languages and restart/migration persistence. Evidence: `outputs/storage-api-full-test.log`.
- Production builds, native C++/CPPIA tests for both ZIP encodings, and formatting checks passed. Native tests execute real plugin modules and extraction through Storage. Evidence: `outputs/storage-api-build.log`, `outputs/storage-api-cppia.log` and `outputs/storage-api-format-check.log`.
- Source scanning found no direct `File`, `FileSystem` or Java filesystem operations in application/plugin/Haxe test source. Production JAR inspection confirms Storage is included and fixture classes are excluded.
- A private backup and existing-installation rehearsal preserved eight stories, five categories, the administrator, subscriber, seven managed images, six menu links, settings and package activation. Backup: `storage/backups/pre-storage-api-20261104-042045/`. The live JVM passed media, package-asset, cached homepage and CSV download/cleanup checks after updating the bundled Newsletter server module. Evidence: `outputs/storage-api-upgrade-verification.json`.

## Native PHP plugin support

Plugin ZIP builds now include a PHP class-map descriptor and package-owned `.php` classes beside the JAR and CPPIA artifacts. PHP hosts select the PHP artifact, enforce the exact CMS/API release and use the shared creation, destruction and JSON hook contracts. Existing dual-target packages remain supported on JVM/C++; PHP hosts reject a missing PHP target.

The PHP loader registers a scoped SPL autoloader, validates the shared interface, and resolves native include paths through Storage. Haxe compiler metadata gives each build an isolated namespace, allowing replacement under the same Haxe entrypoint without PHP class redeclaration. Closing a module removes its autoloader. Upload inspection validates bounded JSON class maps and file references without executing PHP. The portable streaming ZIP reader is shared by C++ and PHP. Native batched routes use HxWell's portable thread-local abstraction.

- Native PHP checks passed for hooks, publication validation, replacement/isolation, invalid interfaces and autoloader cleanup; RSS uses the actual ORM/cache and Newsletter uses package translations and grouped routes. Creation/destruction failures propagate into the shared error records, and ZIP checks cover missing targets, paths, checksums, entry limits, data descriptors and non-execution during inspection. Evidence: `outputs/php-plugins-native.log`.
- The full JVM integration suite passed, including package installation/replacement, PHP class-map rejection cases, admin route guards, lifecycle warnings, translations, cached queries, uploads and restart/migration persistence. Evidence: `outputs/php-plugins-full-test.log`.
- Native C++/CPPIA checks passed for both ZIP encodings, with the PHP artifact present in normal example packages. Evidence: `outputs/php-plugins-cppia.log`.
- Production JVM/web/package builds, type checks and formatting checks passed. Evidence: `outputs/php-plugins-build.log`, `outputs/php-plugins-typecheck.log` and `outputs/php-plugins-format-check.log`. The restarted local JVM also passed homepage/SSR, admin login, existing RSS and new package-download checks without public sessions. Evidence: `outputs/php-plugins-live-check.json`.

The local website uses the JVM host. Native PHP verification uses an isolated PHP CLI host and a separate cache, with database fixtures created only through the test JVM ORM process.

## Professional admin workspace

The publishing studio now uses an ink-blue navigation rail, white work surfaces, a restrained blue action color and locally bundled IBM Plex Sans. The overview combines a publication summary, recent stories/activity and contextual publishing tools. Lists, forms, media, package management, the editor and sign-in share the same scoped design tokens. Public themes retain their own styles. Native CSS nesting keeps studio selectors under the admin/login roots.

Mobile navigation uses a native modal dialog with grouped role-aware links, a persistent account area, Escape support and an inert background. The compact overview table prioritizes story/status on small screens; full collection tables retain horizontal scrolling and their actions. Form labels and editor headings use functional copy, with English/Turkish catalogues and English singular/plural messages. Font files are imported through Vite's asset graph so production addresses include the build prefix and fingerprint. The [official IBM Plex font licence](https://github.com/IBM/plex/blob/master/packages/plex-sans/LICENSE.txt) is included with the source and published font resources.

- Sixteen fresh-profile Chromium screenshots checked overview, lists, editor, media, taxonomies, settings, themes, plugins and sign-in across desktop/tablet/mobile. Actual font loading, page widths, React sign-in, mobile navigation, keyboard/background isolation, Escape and Turkish rendering passed. The public theme has no studio tokens. Evidence: `outputs/admin-theme-browser.json`, `outputs/admin-*.png`.
- The existing 17 HTTP integration checks passed in an isolated database, including authentication, CSRF, content/category editing, image uploads, cache invalidation, subscriptions/export and logout/replay protection. Evidence: `outputs/admin-theme-e2e.log`.
- TypeScript, client/SSR production builds, JVM compilation and repository formatting passed. Evidence: `outputs/admin-theme-typecheck.log`, `outputs/admin-theme-final-web-build.log`, `outputs/admin-theme-staged-build.log`, `outputs/admin-theme-production-build.log` and `outputs/admin-theme-format-check.log`.
- The local JVM was restarted with the new assets. Live checks verified admin SSR/guard, the public homepage/RSS, all three bundled font files, mobile sign-in without overflow and reduced-motion behavior. Previous hashed assets were retained for open browser tabs. Evidence: `outputs/admin-theme-live-check.json` and `outputs/admin-theme-live-browser.json`. Temporary review servers and their final test databases were removed.

## Plugin database extension points

Plugins can define native HxWell models inside their own package and use Schema/query builder APIs directly. `PluginDatabase` supplies stable table namespaces, per-connection named migrations and an indexed plugin/scope/key JSON store. Its SQL projections are specific and bounded; the migration lookup loads only the declared names (at most 128), and a value lookup reads one value. `PluginMigration` callbacks are append-only and idempotent, with an explicit optional transaction for operations that require one. Disabling/removing/reinstalling a package retains its tables, values and migration history. Native context carries the default connection, slug namespace and table prefix.

Newsletter now owns its Subscriber model and initial migration while retaining the existing physical table and data. The legacy core model remains for existing packages/fixtures. The host exports the new APIs to the SDK on all three plugin targets. Framework compatibility changes add single-row upsert, select the native SQLite/MySQL syntax, support older bundled SQLite with an atomic update/conditional-insert savepoint, and preserve a query parent's connection/table/primary metadata in hydrated models. Startup releases its database connection after plugin creation so schema reads cannot retain a startup lock.

- Full JVM regression checks passed, including the new real-package lifecycle suite for independent models, a later column migration, values and retention across disable/uninstall/reinstall. The final focused JVM run also passed after adding SQLite version detection. Evidence: `outputs/plugin-database-full-test.log` and `outputs/plugin-database-integration.log`.
- Native C++/CPPIA and PHP checks execute the same model/migration/store tests. They verify JSON/null/false handling, scoped identity, stable row IDs, migration retry and explicit rollback, alternate connections and native model metadata, with both ZIP encodings covered on C++. Evidence: `outputs/plugin-database-cppia.log` and `outputs/plugin-database-php.log`.
- The framework patch reproduces its source changes from the sibling checkout without modifying that checkout. Production JVM/package builds and repository formatting passed. Evidence: `outputs/plugin-database-production-build.log`, `outputs/plugin-database-packages.log` and `outputs/plugin-database-format-check.log`.
- A private pre-migration backup was taken before updating the JVM and bundled Newsletter package. Bounded ORM snapshots of isolated before/after database copies confirmed identical content/credential/subscription hashes, package settings and activation. Eight stories, five categories, one administrator/subscriber, seven managed image records, six menu links and all eight media files were preserved. Newsletter recorded its first migration once, and the actual admin subscriber page and RSS passed live checks. Evidence: `outputs/plugin-database-upgrade-verification.json`; backup: `storage/backups/pre-plugin-database-20261104-122931/`.

The API and native model/migration examples are documented in `docs/PLUGIN-PACKAGES.md` under “Plugin databases and models”. SQLite UPSERT behavior follows the [SQLite documentation](https://www.sqlite.org/lang_upsert.html); the MySQL form uses [bound duplicate-key updates](https://dev.mysql.com/doc/refman/8.4/en/insert-on-duplicate.html). Native integration verification uses SQLite; no MySQL server was used for these checks.
