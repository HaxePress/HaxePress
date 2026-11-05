# CMS plugin packages, API version 2

Owners install ZIP packages from **Plugins** or **Themes** in the publishing studio. Upload a ZIP, review its manifest, install or replace the existing version, configure its settings, then activate it. Replacement preserves compatible settings and loads the new server module without restarting the host. JVM hosts use JARs, native C++ hosts use CPPIA bytecode, and PHP hosts load native PHP classes.

Every package contains `cms-package.json` at its root, or inside one enclosing folder. Frontend assets live in `public/`. New plugin builds contain JVM, C++ and PHP server artifacts in one ZIP, including plugins whose main contribution is frontend assets. Existing dual-target ZIPs remain compatible with JVM/C++ hosts; PHP hosts require the PHP artifact. A theme provides a stylesheet and one of the supported public layouts: `simple`, `fieldnotes`, `notebook`, `gallery`. Simple is the default. Editorial themes include their own React renderer.

```json
{
  "apiVersion": 2,
  "cmsVersion": "1.0.0",
  "kind": "plugin",
  "slug": "reading-companion",
  "name": "Reading Companion",
  "version": "1.0.0",
  "description": "A reading note for your publication.",
  "author": "Fieldnotes",
  "server": {
    "jar": "server.jar",
    "cppia": "server.cppia",
    "php": "php/module.json",
    "entrypoint": "example.reading.ReadingPlugin"
  },
  "hooks": ["site.shared"],
  "fields": [
    {
      "key": "message",
      "label": "Reading note",
      "kind": "textarea",
      "defaultValue": "A little time for a good story."
    }
  ]
}
```

Optional `assets.module` and `assets.stylesheet` paths are relative to `public/`. JavaScript modules use `.mjs` or `.js`. Stylesheets use `.css`. Theme manifests also contain `"kind": "theme"` and a `layout` value. The inspector rejects missing declared files, traversal/absolute paths, duplicate paths including case aliases, unsupported API versions, more than 256 entries, files larger than 16 MB and total expansion above 32 MB. Compressed ZIP uploads are limited to 10 MB. Extraction streams bytes and does not execute server classes.

Setting kinds are `text`, `textarea`, `boolean`, `number`, `color`, `select`, `secret`. Every field has a distinct lower-case `key`, a label and a string `defaultValue`. Optional fields include `help`, `required`, `minimum`, `maximum`, and `options` containing `{ "value", "label" }` records. Secret fields cannot contain default credentials. Saved secrets are encrypted with the application's key, remain masked in owner page props and are excluded from frontend settings. An empty secret input retains the existing value; the explicit clear control removes it.

## Target-specific server modules

The shared SDK contains `blog.cms.plugins.PluginEntrypoint` with this signature on all three targets:

```haxe
public function onCreate(host:PluginHost, context:String):Void;
public function onDestroy():Void;
public function dispatch(event:String, context:String):String;
```

Context and results are JSON objects; private HTTP request/session objects are not passed through the interface. An empty result is treated as an empty object. Results are limited to 64K characters. Entrypoint classes require a public no-argument constructor and must implement the shared interface.

| Host target | Manifest field | Loader |
| --- | --- | --- |
| JVM | `server.jar` | A version-specific JVM class loader sharing the host API |
| Native C++ | `server.cppia` | `Module.fromData`, `boot`, `resolveClass` and a typed entrypoint instance |
| PHP | `server.php` | A validated JSON class map, scoped SPL autoloader and native PHP entrypoint instance |

`server.entrypoint` is the same Haxe class name for all artifacts. JAR and CPPIA remain mandatory for compatibility with the original package contract. New builds also declare `server.php`, a JSON descriptor beside the compiled `.php` files. The host selects its own artifact and rejects packages missing that target before installation. `cmsVersion` must exactly match the immutable release in `cms.json`; ranges and missing versions are rejected. Installation, activation, replacement and startup validate compatibility before executing plugin code. API 1 plugins must be rebuilt. CSS-only themes retain their existing theme format.

CPPIA hosts require `-D scriptable`, which is included in this project's `global.hxml`. They load modules through Haxe's [native CPPIA Module API](https://api.haxe.org/cpp/cppia/Module.html) and instantiate the declared class without running a script's `main`. Modules are kept separately for each installed generation. Closing a C++ module drops the host references to its instance and loaded module; closing a JVM module also closes its class loader.

Build modules from the matching CMS source checkout with the project's pinned Haxe 4.3.7 / hxcpp 4.3.2 toolchain. `scripts/build_packages.py` and its `build_plugin` helper compile all three artifacts from the same source, using the application's JVM type graph, CPPIA host exports and PHP compiler metadata. The SDK archives contain the shared contracts and exported class list; native framework plugins also need the matching framework sources and compiler configuration. The JVM contract JAR alone does not replace that configuration. ZIP inspection validates declared artifacts and the CPPIA header before installation; class linking and interface validation occur when the selected module is loaded.

Declared event hooks are `site.shared`, `content.render`, `content.saving`, `content.saved`, `dashboard.widgets`, `ui.navigation`, and the automatically registered `site.assets` hook. `onCreate` runs when an enabled plugin starts, including process startup and activation. `onDestroy` runs on disable, replacement, uninstall and graceful JVM shutdown. `settings.saved` is dispatched to an already running instance when its settings change. Installing an inactive package does not execute its code.

The JSON context contains `apiVersion`, `cmsVersion`, `packageInfo`, `settings`, `site` and `data`. Server modules receive decrypted settings; browser modules receive public settings only.

| Event | Data | Result |
| --- | --- | --- |
| `site.shared` | `{ path }` | `{ blocks: [{ slot, content }] }` with Markdown content |
| `content.render` | `{ document, content }` | `{ content }` with transformed Markdown; stored content is unchanged |
| `content.saving` | `{ document }` | `{ error }` to reject a manual save with a readable message |
| `content.saved` | `{ document }` | Notification after a save or scheduled publication |
| `dashboard.widgets` | `{ summary }` | Markdown blocks with `slot: "dashboard"` |
| `ui.navigation` | `{ location, capabilities }` | `{ items: [{ label, href, icon }] }` for `header`, `footer` or `admin` |

Public block slots are `site.top`, `site.before-footer`, `site.footer`, `article.before` and `article.after`. Content uses escaped, GFM-compatible Markdown. Content render transformations retain the managed-image requirement. Public hook failures disable the affected package and record the error; validation hook failures reject the save. Inactive packages have no running instance.

Frontend modules export `activate({ root, settings, path, slot })`. Return a cleanup function, or export `deactivate(context)`. Cleanup runs on navigation and when settings/assets change. Stylesheets use Inertia's Head component. Asset addresses include the installed package generation, so updates receive new URLs. Disabled package assets return 404.

JAR, CPPIA, PHP and frontend modules execute trusted owner-supplied code with the application's permissions. ZIP inspection validates structure and limits; it does not sandbox that code. Install packages from sources you trust. The example package is maintained in this repository.

The example Haxe module is in `examples/plugins/reading-companion/`. During development the SDK/example can be built against the isolated test application:

```sh
python3 tests/build.py
python3 scripts/build_packages.py --application Export/tests/hxwell.jar
```

`make build` generates artifacts under `Export/packages/` and copies them to `public/packages/`: the JVM contracts in `cms-plugin-api-2.jar`, the shared Haxe interfaces and CPPIA exports in `cms-plugin-api-2.zip`, three JVM/CPPIA/PHP plugin ZIPs (`reading-companion`, `rss`, `newsletter`), and four theme ZIPs. Reading Companion adds a footer note, a browser reading-progress indicator and a dashboard widget. Settings can append a note to articles and enforce a minimum publication length. Tests compile a changed module under the same entrypoint name and verify that replacement executes its new classes while preserving settings.

Only one theme is active at a time, and at most 32 plugins can be active. Theme settings support color, typography and publication width. Preview uses actual published content and menus without changing the active theme. Activate another theme before uninstalling the current one. Uninstall removes package settings, hook registrations and managed files; editorial content is retained.

## Verification

```sh
make test
make test-cppia
make test-php
```

The JVM suite exercises real JAR installation/replacement and rejects every single-target or wrong-release plugin ZIP. `make test-cppia` requires a C++ toolchain and builds an isolated native host. It verifies target selection, shared-interface checks, hook dispatch, validation, replacement under the same entrypoint name, module isolation, close behavior and bounded ZIP decoding, including data descriptors and invalid checksums. The deployed CMS currently runs on JVM. The C++ and PHP commands verify the plugin subsystem through isolated native hosts. `make test-php` requires PHP CLI with mbstring, OpenSSL and SQLite support. It executes actual PHP classes, RSS ORM queries, Newsletter routes/translations, same-entrypoint replacements, interface rejection, autoloader cleanup and lifecycle failure handling.

Setup installs hxcpp in the project's local Haxelib repository. `patches/hxcpp-macos-zlib.patch` keeps modern Darwin SDKs out of the bundled zlib's classic-Mac compatibility branch. A local `haxe-concurrent` copy receives `patches/haxe-concurrent-cppia.patch` to give inherited lock methods concrete CPPIA bridge declarations. `patches/hxwell-plugin-routes.patch` adds native batched route registration/removal and route attributes. Global Haxelib installations and sibling framework sources are preserved.

## PHP modules

The PHP descriptor contains data only; uploading or inspecting a package never includes its PHP files:

```json
{
  "namespace": "CmsPlugin_0123456789abcdef0123456789abcdef",
  "entrypoint": "example.reading.ReadingPlugin",
  "classes": {
    "CmsPlugin_0123456789abcdef0123456789abcdef\\example\\reading\\ReadingPlugin": "lib/CmsPlugin_0123456789abcdef0123456789abcdef/example/reading/ReadingPlugin.php"
  }
}
```

Class-file paths are relative to the descriptor's directory. Inspection checks a maximum of 128 class mappings, safe paths, an exact entrypoint match, isolated names and the presence/size of every declared PHP file. The 64 KB descriptor, files and archive stay within the existing ZIP expansion limits. Missing, duplicate or out-of-namespace class mappings are rejected on every host, including JVM.

The build helper uses Haxe's native `@:native` metadata to give package-owned classes a unique `CmsPlugin_<build-id>` namespace. Keep plugin classes below the entrypoint's Haxe package. Host classes retain their normal names, so the plugin uses the host's HxWell routes, ORM, Storage and translations. The ZIP contains only package-owned PHP classes; it does not include another Haxe runtime or framework. The entrypoint's Haxe name and lifecycle contract stay the same across all three artifacts.

The PHP host must retain its exported API graph (`-dce no` in the native test host), including `Xml` for RSS. Keep `CACHE_PATH` separate between PHP and JVM/C++ processes: the installed framework uses PHP-native serialization on PHP and Haxe serialization on the other targets. The PHP check uses a separate cache while the test-only JVM ORM fixture prepares the database.

On activation, the PHP backend registers an [SPL autoloader](https://www.php.net/manual/en/function.spl-autoload-register.php) for that module's exact class map, obtains physical paths through `Storage.path()` at the native `require_once` boundary, checks the shared interface and constructs the entrypoint. `close()` removes the autoloader and drops the instance. PHP retains already declared classes until the request/process ends; the build namespace lets changed generations coexist without redefining them. A replacement build receives a new namespace and can execute alongside the prior generation. No source rewriting or `eval` is used.

## Native lifecycle and routes

Plugins can use the installed HxWell route, handler, validation, Schema and ORM APIs. Build native plugins against the same CMS source release. `scripts/build_packages.py` uses the application's JVM type graph, then removes host-supplied classes from the plugin JAR without changing its bytecode. CPPIA compilation uses the exported host class list. This retains the Haxe calling conventions used by native framework classes.

```haxe
import blog.cms.plugins.PluginHost;
import hx.well.route.Route;
import hx.well.route.RouteElement;

var feedRoute:RouteElement;

public function onCreate(host:PluginHost, context:String):Void {
    feedRoute = Route.get("/rss.xml", new RssHandler());
}

public function onDestroy():Void {
    Route.unregister(feedRoute);
}
```

The host batches route changes through `Route.batch`, publishes complete route snapshots, tracks created routes and removes remaining owned routes when stopping the plugin. `host.admin(callback)` registers routes under the existing `/admin` session, CSRF and authentication middleware. `host.can(capability)` checks the current administrator's server-side permissions. A route can set `.attribute("inertia.share", false)` for feeds, JSON or downloads that do not need shared page props.

Creation or destruction exceptions disable the plugin, preserve the error on its card and set a process-wide restart warning. Managed route cleanup is still attempted. A plugin with a lifecycle error cannot be reactivated or replaced until restart. Removing a failed package does not hide the process warning; a new process clears it. Other plugin side effects can require a restart even after managed routes are removed.

RSS Feed and Newsletter are bundled native plugins, installed and enabled once to preserve the previous site behavior. Their handlers and subscription form live under `examples/plugins/`. Disabling RSS removes its feed route and footer link. Disabling Newsletter removes signup/admin routes, navigation, widget and frontend form assets. Subscriber data remains in the database. The newsletter heading is configured through the plugin's settings; the old setting is imported on the first upgrade.

`ui.navigation` receives `{ location, capabilities }` and returns `items` with `label`, `href` and `icon` for `header`, `footer` or `admin`. Native plugin handlers can render `Admin/PluginPage` with generic table/page props; the core contains no subscriber-specific controller or component.

## Plugin databases and models

A plugin can keep its own model classes inside its source package. Extend HxWell's `BaseModel`, declare `@:table`, `@:primary`, `@:field` and `@:visible`, and use `Model.query` normally. Plugin models are compiled into the selected JAR/CPPIA/PHP module; adding a model does not require editing the CMS model folder. The Newsletter source demonstrates this with `extensions.newsletter.Subscriber`. Its existing `subscribers` table is retained so upgrades preserve subscriptions; the core Subscriber type remains available for older packages and test fixtures.

Use `PluginDatabase.table(slug, suffix)` in the model metadata and the same name in Schema calls. Slugs are package manifest slugs, without the CMS's `plugin-` ID prefix. Short slugs produce names such as `plugin_bookmarks_entries`; long slugs receive a deterministic shortened namespace. Identifiers stay within 64 characters, and table suffixes accept at most 32 lowercase letters/digits/underscores. This naming convention avoids accidental collisions; trusted native plugins still have the application's database permissions.

```haxe
package extensions.bookmarks;

import blog.cms.plugins.PluginDatabase;
import hx.well.model.BaseModel;
import hx.well.model.BaseModelQuery;

@:table(PluginDatabase.table("bookmarks", "entries"))
class Bookmark extends BaseModel<Bookmark> {
    public static var query:BaseModelQuery<Bookmark>;

    @:primary @:visible @:field public var id:Int;
    @:visible @:field public var title:String;
    @:visible @:field public var post_id:Int;
}
```

Run append-only, named migrations from `onCreate`, before registering routes that use their tables:

```haxe
import blog.cms.plugins.PluginDatabase;
import blog.cms.plugins.PluginMigration;

var database = new PluginDatabase("bookmarks");
var schema = database.schema();
var tableName = database.tableName("entries");
database.migrate([
    new PluginMigration("001_create_entries", () -> {
        if (!schema.hasTable(tableName)) {
            schema.create(tableName, table -> {
                table.id();
                table.string("title");
                table.integer("post_id");
                table.index(["post_id", "id"]);
                table.foreign("post_id").references("id").on("posts").cascadeOnDelete();
            });
        }
    })
]);

var rows = Bookmark.query.select(["id", "title", "post_id"])
    .where("post_id", postId)
    .orderBy("id")
    .limit(20)
    .get();
```

Migrations run in the supplied order. Each successful name is recorded once per plugin/connection in `plugin_migrations`; the history has no cascading dependency on installed package generations. New package versions append migrations. Startup, reactivation and replacement skip recorded names. The runner validates the complete list before execution and loads only the declared names, with a maximum of 128 migrations per call. A failure propagates to the existing plugin lifecycle error/restart warning and is not recorded as completed.

Write idempotent migration callbacks: a process can stop after a schema change but before its history record is written. Native Schema methods such as `hasTable`/`hasColumn` and `whenTableDoesntHaveColumn` help make retries safe. There is no implicit transaction around every callback. For compatible operations that require data and the history row to commit together, pass `true` as the third `PluginMigration` constructor argument. HxWell's SQLite column changes can manage their own savepoints/foreign-key handling, so those migrations should retain the default `false`. Use new names when changing already applied migrations.

For small JSON state or extra content fields, a plugin can use the built-in value store:

```haxe
var database = new PluginDatabase("bookmarks");
database.put("sync-cursor", {after: 120, complete: false});
var cursor = database.get("sync-cursor", null);

database.put("reading-note", {text: "Return to this later", tags: ["ideas"]}, "post:42");
var note = database.get("reading-note", null, "post:42");
var exists = database.has("reading-note", "post:42");
database.forget("reading-note", "post:42");
```

Every lookup includes the plugin slug, scope and key and selects at most one value. Writes use the native builder's single-row `upsert(data, uniqueBy, updateColumns)` through a reproducible framework compatibility patch. They preserve the row identity. Modern SQLite (3.24+) uses one native UPSERT statement, and MySQL uses its native duplicate-key form. The framework detects the older SQLite bundled with this hxcpp toolchain and uses an update/conditional-insert inside a savepoint only for that engine; this keeps the operation atomic and also works inside an explicitly transactional migration. SQL generation stays inside the framework compatibility patch. Stored `null`, `false` and missing keys remain distinct through `has` and the explicit fallback. Keys/scopes are limited to 128 UTF-8 bytes without control characters; JSON values are limited to 65,535 bytes. Use plugin-owned models for larger/queryable data and native Cache/Storage APIs as appropriate. There is no whole-plugin value load/filter API.

The default connection uses the same configured database as the CMS. `new PluginDatabase(slug, connectionName)` can use another connection registered with HxWell; call `initialize()` once before using its value store, or let `migrate()` initialize its history/store tables. `schema()` returns the installed native `SchemaBuilder` for that connection. Models use HxWell's `@:connection` metadata; dynamically configured model/query parents retain their connection/table/primary metadata when rows are hydrated. Native plugin event context also includes `database: { connection, namespace, tablePrefix }`.

Disabling or uninstalling a plugin removes its running code/routes/package files and retains its tables, values and migration history. Reinstalling under the same slug can resume them. Data removal remains an explicit plugin operation. Cache plain `toObject()` records rather than live models, and keep queries/projections/pagination bounded just as in core code.

The test package in `tests/plugins/database/` demonstrates an independent model, relational table, a later column migration and scoped JSON. JVM lifecycle tests install/update/uninstall/reinstall real packages. The native C++ and PHP hosts execute the same model/migration/store checks against SQLite, including retry/transaction behavior, stable upserts and alternate connections.

## Shared translations

Core pages, native plugins, browser modules and themes use the same translation catalogues. English is the fallback and initial default. English and Turkish are included. Visitors choose a language in the public footer or studio header; owners configure the default under Settings. A `lang` query parameter overrides the preference for one request. Selecting a preference posts to `/locale` and sets a separate `cms_locale` cookie without opening a session.

Declare catalogue paths in a plugin or theme manifest:

```json
"translations": {
  "en": "lang/en.json",
  "tr": "lang/tr.json"
}
```

Include those files in the ZIP alongside the existing modules/assets. Files contain a flat JSON object. Keys may be English source messages or stable identifiers:

```json
{
  "Hello {name}": "Merhaba {name}",
  "Story count": {
    "one": "{count} yazı",
    "other": "{count} yazı"
  }
}
```

The host validates every declared catalogue during upload: at most 10 locale files, 128 KB and 1500 messages per file, 500 characters per key and 4000 per translation. Plural messages require `one` and `other`. Missing keys fall back to the package's English catalogue, then core messages, then the original key. Named placeholders are replaced once; unknown placeholders remain visible. Messages are plain text, so renderers retain responsibility for escaping their output.

Each package has its own namespace: `plugin-{slug}` or `theme-{slug}`. Packages cannot replace another namespace. Public React pages check the active theme's catalogue before core messages, allowing themes to translate their own labels and override public copy. Studio components use the core namespace. Inactive-theme previews load that theme's catalogues without activating it; owner settings pages can use an inactive package's labels.

Native Haxe code uses the shared service:

```haxe
import blog.i18n.I18n;

var greeting = I18n.t("Hello {name}", ["name" => "Alex"], "plugin-my-plugin");
var currentLocale = I18n.locale();
```

Locale belongs to the current request. Startup callbacks and background work use the configured default; event context also includes `locale`. An explicit fourth argument to `I18n.t` selects a locale for background work. Native plugins compile this host service externally, like the other HxWell APIs.

Browser modules receive a translator already bound to their package namespace:

```js
export function activate({ locale, t, slot }) {
  const greeting = document.createElement('p');
  greeting.textContent = t('Hello {name}', { name: 'Alex' });
  slot('site.footer')?.append(greeting);
  return () => greeting.remove();
}
```

React source uses `useTranslation()` from the application's `i18n` module, or `useTranslation('plugin-my-plugin')` for an explicit namespace. `Admin/PluginPage` accepts a `namespace` in its `pluginPage` props for column headings, actions and empty states. Modules are cleaned up and mounted again when the locale changes. SSR and client navigation receive the same selected locale and catalogues; document `lang`/`dir` and `Content-Language` follow it.

Catalogue caches include package identity, installed generation and locale. Activation, replacement and uninstall invalidate them. Only active package catalogues are shared publicly; metadata queries select `id`, `directory` and `manifest` in bounded results. Editorial content, stored settings and query-result caches keep their original values; translation happens while preparing/rendering responses.

Core catalogues live in `resources/lang/`. To add another supported language, add its catalogue, register its code/name/direction in `I18n.locales`, and include its resource in `global.hxml` and the native plugin build options. Rebuild both frontend and server artifacts. Bundled RSS, Newsletter, Reading Companion and theme source provide working catalogue examples.

## Theme renderers

Simple is a built-in, single-column default with system typography and plain article lists. Fieldnotes preserves the original editorial design as an installable package. Its public page components, stylesheet, fonts, image and translations live under `examples/themes/fieldnotes/`; they are bundled into the ZIP. Notebook and Gallery build on that source, and each ZIP contains the complete renderer and styles it needs.

Renderer themes use API 2 and an exact `cmsVersion`, with this asset declaration:

```json
"assets": {
  "stylesheet": "theme.css",
  "renderer": "theme.mjs"
}
```

The self-contained ES module exports `createTheme(runtime)`, returning a `pages` map for `Home`, `Journal`, `Story`, `ContentPage`, `About` and `NotFound`. Page components receive the existing bounded Inertia props. A page's optional `layout` function wraps it, following the Inertia React convention. `runtime` supplies the host's React instance, Inertia navigation/hooks, translated/shared UI primitives and `asset(path)` for files in the package's `public/` directory. Keeping React in the host ensures hooks and hydration share one runtime.

Source examples use TypeScript and JSX. `npm run build:themes` compiles them with the classic `React.createElement` JSX transform into `Export/themes/`, including renderer code and scoped styles. `scripts/build_packages.py` creates installable archives from that output. No DOM replacement or markup-hiding step is used to choose a layout: the selected package supplies actual React page components.

The browser imports the generation-specific renderer URL. The SSR worker imports the same installed module from its local storage directory before rendering. Set `CMS_STORAGE_PATH` on a separately managed SSR worker to the same absolute storage directory used by the JVM. `scripts/run.py` and isolated integration runners set it automatically. Public/preview asset URLs remain subject to normal active-theme and owner checks. Theme code is trusted owner-supplied code and executes in the SSR process as well as the browser.

The default-theme upgrade installs Simple, updates the bundled editorial packages while retaining their settings, and selects Simple once. Subsequent starts retain the owner's chosen theme. Fieldnotes can be previewed, activated or uploaded again through the normal Themes panel.

Theme previews use an administrator-owned outer page with a toolbar and a separate iframe document. Theme CSS and renderer assets load only inside that frame; page layouts do not render a preview toolbar. The frame uses protected `/admin/themes/{id}/preview/content` routes and same-origin framing headers. Normal pages retain their existing frame restrictions.

The host's `Link` component keeps public-page navigation inside the selected preview. `useSiteHref()` is available on the theme runtime for GET forms and direct router calls, for example `router.get(siteHref('/journal'), filters)`. Public rendering returns ordinary addresses. The preview scope and locale travel with frame navigation without activating the theme.
