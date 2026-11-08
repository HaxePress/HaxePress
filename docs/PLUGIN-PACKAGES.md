# HaxePress extension packages, API 4

Owners upload ZIP packages from **Plugins** or **Themes**, review their manifest, install or replace a version, configure settings and activate it. Native code starts on activation/startup, after compatibility checks. Inspecting an archive does not execute its server code.

On JVM sites, **Plugins → Install from GitHub** accepts a public GitHub repository or its Releases URL. Choose a release ZIP, inspect its manifest, then use the normal install or replace action. The picker lists uploaded release assets up to 64 MB. Publish a HaxePress package ZIP containing the native modules for the exact CMS version. GitHub's automatically generated source archives are outside the picker. [GitHub release assets](https://docs.github.com/en/rest/releases/assets)

The example repository publishes a ready-to-install package for HaxePress 2.16.0. Its source and build instructions are also in `examples/plugin-repository`. [Example plugin releases](https://github.com/hxwell/haxepress-plugin-example/releases)

Set `TEST_GITHUB_RELEASE=true` when running `python3 tests/run.py --only cms_packages` to include a live installation from the example release.

CMS **2.16.0 / API 4** uses the `hx.press.*` application namespace, `ContentItem` / `content_items` for content storage, and the public pages listed below. Rebuild older native plugins for this exact release. The bundled upgrade retains package settings, activation and the selected theme.

Simple is embedded in the application and is not distributed as a replaceable ZIP. Theme cards use real isolated preview frames; custom `simple` layouts may inherit the application's bundled CSS. See [themes](THEMES.md).

## Package manifest

```json
{
  "apiVersion": 4,
  "cmsVersion": "2.16.0",
  "kind": "plugin",
  "pluginId": "73bd51b4-a55b-4f34-8b3c-2016b19fb0f4",
  "slug": "my-extension",
  "name": "My extension",
  "version": "2.16.0",
  "description": "Adds a feature to your site.",
  "author": "Package author",
  "server": {
    "jar": "server.jar",
    "cppia": "server.cppia",
    "php": "php/module.json",
    "entrypoint": "extensions.example.ExamplePlugin"
  },
  "hooks": ["site.shared"],
  "translations": {
    "en": "lang/en.json",
    "tr": "lang/tr.json"
  },
  "fields": [
    { "key": "enabled", "label": "Enable feature", "kind": "boolean", "defaultValue": "true" }
  ]
}
```

Place `cms-package.json` at the archive root or inside one enclosing folder. Frontend files live in `public/`; optional `assets.module` and `assets.stylesheet` refer to `.js`/`.mjs` and `.css` files there, and `assets.views` names a folder of Wellout templates for the plugin's pages (see [Plugin pages](#plugin-pages)). Optional `locks` lists the host locks the plugin holds while it runs (see [Upload limits and host locks](#upload-limits-and-host-locks)). The normal builder emits all three server targets. JAR and CPPIA remain required; PHP hosts also require `server.php` and its declared classes. `cmsVersion` is an exact release, rather than a version range. API 1/2/3 metadata can be read during upgrades; it does not authorize executing incompatible server modules.

Generate one lowercase UUID for the plugin project and declare it in `pluginId`. Keep it across releases. Installation rejects a UUID owned by another package and updates must retain the installed UUID. An existing package that predates this field adopts the UUID from its first updated ZIP. Themes use their usual theme IDs.

The default RSS, Newsletter, Cloudflare, View Count and JVM Backups plugins are installed from the packages shipped with HaxePress. Startup upgrades them from the current shipped artifacts while preserving compatible settings and activation. Their lifecycle controls are **Activate** and **Deactivate**.

Packages are capped at 64 MB compressed, 128 MB expanded, 16 MB per file and 256 archive entries. The HTTP upload configuration can impose a lower limit on local uploads. Inspection validates paths, duplicates/case aliases, declared assets, translation files and native artifact structure. Extraction streams bounded entries through Storage. Server modules and browser/SSR code are trusted owner-supplied code with the application's permissions.

Setting kinds are `text`, `textarea`, `boolean`, `number`, `color`, `select` and `secret`. Fields have unique lowercase keys, labels and string defaults, with optional help/required/minimum/maximum/options. Secrets have no default credentials, are encrypted, masked in owner props and omitted from public settings. An empty secret retains its old value; clearing is explicit. Replacement preserves settings whose names and kinds still match.

## MCP tools

Expose a plugin action as an MCP tool by adding `cms.mcp` metadata to a concrete route registered inside `host.admin`.

```haxe
host.admin(() -> {
    Route.get("/inventory/search", new SearchInventoryHandler())
        .attribute("cms.mcp", {
            name: "search",
            description: "Search the site's inventory by product name.",
            capability: "inventory",
            inputSchema: {
                type: "object",
                properties: {query: {type: "string", maxLength: 80}},
                required: ["query"]
            }
        });
});
```

The exported name starts with `plugin_` and includes the plugin slug. The tool uses GET by default. Set `method` to `POST` or `DELETE` for a matching route that changes data. The host passes GET arguments as query parameters and write arguments as JSON. HaxePress checks the declared capability and runs the native handler and its validators. The declaration defaults to the `extensions` capability. Use fixed route paths and bounded JSON object schemas. Plugin tools follow the plugin's activation and route lifecycle.

## Native lifecycle and routes

All server targets implement the shared Haxe contract:

```haxe
import hx.press.plugins.PluginEntrypoint;
import hx.press.plugins.PluginHost;

class ExamplePlugin implements PluginEntrypoint {
    public function new() {}

    public function onCreate(host:PluginHost, context:String):Void {}
    public function onDestroy():Void {}
    public function dispatch(event:String, context:String):String {
        return "{}";
    }
}
```

Contexts/results are JSON objects. An empty result is treated as an empty object, and returned JSON is limited to 64K characters. The context contains `apiVersion`, `cmsVersion`, `locale`, `packageInfo`, `database`, decrypted server `settings`, site settings and event `data`.

### Scheduled tasks

In `onCreate`, register an optional persistent job with `host.schedule(pluginId, key, intervalSeconds, payload)`. Read `packageInfo.pluginId` from the creation context. The host checks it against the plugin's installed UUID. Use a stable lowercase key and optional JSON object payload. Registering the same definition again keeps its next due time.

Tasks a user manages, such as backup schedules, use `host.saveSchedule(pluginId, key, intervalSeconds, payload, enabled, nextRun)`, which creates or replaces a task with its first run in epoch milliseconds (one interval from now when omitted). `host.schedules(pluginId, limit)` returns the plugin's tasks as a JSON array of `key`, `payload`, `intervalSeconds`, `enabled`, `nextRun`, `lastRun`, `lastError` and `running`, soonest first.

The runtime calls `dispatch("schedule.run", context)` on the active plugin. The event's `data` includes `id`, `key` and the parsed `payload`. Return an empty object on success or an object with an `error` message to record a failed run. Keep effects idempotent across an interrupted run. Use `host.unschedule(pluginId, key)` to remove a rule; it returns false while a run holds the task. Deactivation pauses the plugin's jobs and uninstall removes them. Core jobs have a null plugin ID. Each plugin can provide management controls on its own admin page through `host.admin` and native `cms.navigation` or `cms.settings` route metadata.

### Server modules

| Target | Module         | Loading                                                        |
| ------ | -------------- | -------------------------------------------------------------- |
| JVM    | `server.jar`   | A generation-specific class loader sharing the host API        |
| C++    | `server.cppia` | Native CPPIA module boot/class resolution with `-D scriptable` |
| PHP    | `server.php`   | Validated JSON class map and a scoped SPL autoloader           |

`server.entrypoint` is the same Haxe name across targets. PHP class maps reference package-owned `.php` files relative to the descriptor and use a `CmsPlugin_<build-id>` namespace. Native `@:native` compiler metadata creates those isolated names; the host runtime/framework is shared. Closing drops the instance and removes the PHP autoloader or closes the JVM loader. Previously declared PHP classes remain until request/process end; separate build namespaces allow changed generations to coexist. PHP hosts retain the exported API graph, including `Xml` for RSS. Keep PHP's native-serialization cache path separate from JVM/C++ caches.

Use native HxWell routes, handlers, validation and responses. `host.admin(callback)` places extension routes under the existing admin session/CSRF/auth middleware, and `host.can(capability)` checks the current user's permission. Track route handles and unregister them in `onDestroy`:

```haxe
import hx.well.route.Route;
import hx.well.route.RouteElement;

var route:RouteElement;

public function onCreate(host:PluginHost, context:String):Void {
    host.admin(() -> {
        route = Route.get("/my-extension", new ExampleHandler());
    });
}

public function onDestroy():Void {
    Route.unregister(route);
}
```

The host batches route registration and tracks ownership. Stopping a module removes remaining managed routes even when destruction throws. Creation/destruction failures disable the affected plugin, retain its error and show a process-wide restart warning. Installing an inactive package does not execute it. Disable, replacement, uninstall and graceful JVM shutdown destroy running instances; settings changes dispatch `settings.saved` to an active instance.

A plugin's administration page renders the standard `Admin/PluginPage` view: `Pages.render("Admin/PluginPage", {pluginPage: page})`, with `import hx.press.view.Pages;` (the SDK exports it for every target; the JVM host renders the page). `page` holds a `title`, `description`, `total`, `columns` (`key`, `label`), `rows`, `actions` (`label`, `href`, optional `download`), an optional `rowAction` (`label`, `path` with `{id}`, `confirm`), `pagination` from `Pagination.links` and a `noun`. Texts are keys in the plugin's `namespace`. The page is rendered on the server inside the administration layout; the newsletter example's subscriber list shows the whole shape.

### Middleware

A plugin can run HxWell middleware on every request. Add it in `onCreate` and remove it in `onDestroy`, like routes:

```haxe
import hx.press.plugins.PluginMiddleware;

var middleware:PluginMiddleware;

public function onCreate(host:PluginHost, context:String):Void {
    middleware = PluginMiddleware.add(ExampleMiddleware);
}

public function onDestroy():Void {
    PluginMiddleware.remove(middleware);
}
```

`ExampleMiddleware` extends `hx.well.middleware.AbstractMiddleware`. Plugin middleware runs after the application's global middleware and before route middleware, in the order plugins added it; HxWell creates an instance for each request and disposes it afterwards, after the response has been sent, so keep shared state in immutable or static values. The runtime records the middleware a plugin adds while it is created: a failed creation removes it, and stopping a plugin removes whatever `onDestroy` left. A request keeps the list it started with, so a removal applies to the requests that start after it. The bundled Cloudflare plugin (`examples/plugins/cloudflare`) uses this to set `request.ip` from `CF-Connecting-IP` and the `cms.visitor.country` attribute from `CF-IPCountry` on connections from Cloudflare.

### Content views

The application tells plugins which published content item a page shows and what it knows about the visitor; what counts as a visit, how counts are kept and where they go is each plugin's own choice. A plugin that counts visits adds middleware (see [Middleware](#middleware)), reads the request after `next(request)` returns, so the order of plugin middleware does not matter, and records its count in `dispose`, which HxWell calls after sending the response:

```haxe
class VisitMiddleware extends AbstractMiddleware {
    var id = 0;

    public function handle(request:Request, next:Request->Null<Response>):Null<Response> {
        var response = next(request);
        var shown:Dynamic = ContentViews.content(request);
        if (shown != null && request.method == "GET" && !ContentViews.member(request)) {
            id = shown.id;
        }
        return response;
    }

    public override function dispose():Void {
        if (id > 0) {
            Visits.add(id); // the plugin's own buffer
        }
        super.dispose();
    }
}
```

| Name                            | Use                                                                                                                                                  |
| ------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ContentViews.CONTENT`          | Request attribute `cms.content`: `{id, type}` of the published content item the page shows; set while it renders, also for previews.                 |
| `ContentViews.content(request)` | That value, or null.                                                                                                                                 |
| `ContentViews.COUNTRY`          | Request attribute `cms.visitor.country`: two uppercase letters, set only by a plugin that trusts the connection's proxy.                             |
| `ContentViews.country(request)` | That country, or null.                                                                                                                               |
| `ContentViews.MEMBER_COOKIE`    | `cms_member`, which the administration sets for the whole site while a member is signed in. It grants nothing; public pages have no session to read. |
| `ContentViews.member(request)`  | Whether that cookie is present.                                                                                                                      |

The `site.shared` hook receives the same `content` on pages that show a published item, so a plugin can add a block about it. The bundled Cloudflare plugin sets `cms.visitor.country` from `CF-IPCountry` on the connections it trusts, ignoring `XX`, Tor's `T1` and malformed values; a plugin for another trusted proxy can set it the same way. To keep page views from writing to the database, collect counts in memory on the JVM, or append them to a file of the minute with `Storage.append` on PHP, where each request is a new process, and write them from a job (`host.schedule`); `Model.query.upsertIncrement(data, uniqueBy, increment)` inserts `data`, or adds the supplied values of the `increment` columns to the row with the same `uniqueBy` values, in one statement. Pages served from a cache in front of the site, such as a Cloudflare rule that caches HTML, are not seen.

The bundled View Count plugin (`examples/plugins/view-count`) works this way, and all its rules are in the plugin. `ViewRules` counts a GET of a public page that shows a published content item and answers 200, and leaves out HEAD requests, previews and other administration pages, signed-in members' browsers, clients that do not send a browser's `User-Agent`, crawlers, link previews and speculative loads (`Sec-Purpose`, `Purpose`, `X-Purpose`, `X-Moz`). `ViewBuffer` keeps the counts in memory on the JVM, and writes them when the plugin stops too; on PHP a view appends one line to the file of its minute in `storage/view-count/pending`. The plugin's `flush` job writes them once a minute in transactions of up to 500 counts; run `schedule:run` from cron on PHP so they are written when the site is quiet. It keeps one row per content item. Its page under **View counts** lists the most viewed content, `/admin/view-counts/data` answers the same as JSON (`content`, `cursor`, `limit` up to 100) and as the MCP tool `plugin_view_count_views`, the dashboard shows the total, and its settings can show the count before or after the content of public pages. Its **Count views by country** setting, off by default, keeps one row per content item and country as well, listed under **Views by country** (`/admin/view-counts/countries`) with filters by content and country, `/admin/view-counts/countries/data` (`content`, `country`, `cursor`, `limit`) and the MCP tool `plugin_view_count_country_views`. Countries come only from the Cloudflare plugin: without it, or on a connection it does not trust, a view counts as `UNKNOWN`, and the page says when the setting is off or the Cloudflare plugin is inactive. Its pages need the `view_counts` capability.

### Content list columns

The admin list of every collection shows its own columns (the item, status, category and last update), the custom fields shown in lists and the columns of active plugins. Each member chooses which of them they see with the list's **Columns** control and drags them into order there (or focuses a column's handle and uses the arrow keys), and sorts the list by any visible column from its heading. The choice is kept per member and collection in `admin_preferences`.

A plugin adds a column in `onCreate` and removes it in `onDestroy`:

```haxe
import hx.press.content.ContentColumns;
import hx.press.content.ContentColumns.ContentColumn;
import hx.press.plugins.PluginDatabase;

var column:ContentColumn;

public function onCreate(host:PluginHost, context:String):Void {
    column = ContentColumns.add({
        key: "views",
        label: "Views",
        table: PluginDatabase.table("view-count", "totals"),
        value: "views",
        kind: "number",
        empty: "0",
        capability: "view_counts"
    });
}

public function onDestroy():Void {
    ContentColumns.remove(column);
}
```

| Field         | Meaning                                                                                            |
| ------------- | -------------------------------------------------------------------------------------------------- |
| `key`         | Lowercase letters, digits and underscores, unique in the plugin; the column is `<plugin ID>.<key>` |
| `label`       | The heading, a key in the plugin's catalogue (`namespace` names another)                           |
| `table`       | A table of the plugin itself (its `PluginDatabase` prefix) with at most one row per item           |
| `content`     | The column holding the content item's ID; `content_id` when left out                               |
| `value`       | The column shown and sorted; it must not hold null                                                 |
| `kind`        | `number` (the default) or `text`                                                                   |
| `empty`       | What an item without a row shows; `—` when left out                                                |
| `collections` | The collection keys that show it; every collection when left out                                   |
| `where`       | Column values the rows must have, such as `{country: "TR"}`                                        |
| `capability`  | The capability a member needs to see it                                                            |

The list reads a column's value in its own query with a subquery on the plugin's table, so a page reads nothing more than its rows. Sorting by a column happens in SQL, and pages continue with a cursor on the sorted value and the item ID; an item without a row sorts lowest, last when descending and first when ascending. Index `(value, content)` for lists that sort by it. Pages that show or sort by a plugin column are not cached, because the content cache does not follow plugin tables.

A new column is visible until a member hides it, and appears beside the column it follows by default. While its plugin is inactive the column is not offered; members' choices keep its place and visibility for when the plugin returns. The runtime records the columns a plugin adds while it is created, so a failed creation removes them and stopping the plugin removes what `onDestroy` left. The bundled View Count plugin adds its **Views** column this way.

### Plugin pages

A plugin can also ship its own pages as Wellout templates. Name the folder in the manifest as `"assets": {"views": "views"}` and render a template from one of the plugin's routes with `Pages.view("Reports", props)`, which renders `views/Reports.well.html`. Plugin templates are looked up first, then the application's components, so a page can use `AdminLayout`, `Alert` or `Pagination`. `t()` reads the plugin's catalogue first, `packageAsset("reports.css")` links a file from the package's `public/` folder, and a page adds its stylesheet in `<well:head>`.

`views/contract.json` declares the view types the templates read and the islands they mount:

```json
{
  "views": {
    "ReportView": { "title": "String", "rows": "List<ReportRowView>", "next": "Url?" },
    "ReportRowView": { "label": "String", "total": "Int" }
  },
  "islands": {
    "report-chart": { "module": "chart.js", "props": { "rows": "Int" }, "messages": ["Loading"] }
  }
}
```

Types use the template type syntax and may refer to each other and to the application's view types. An island module is an ES module in `public/` that exports `mount(element, props, messages)`; it receives only its declared props and the translated `messages`. Installation checks the contract and compiles every template, and rejects a package whose pages do not compile, with the first problem's position. `haxe tools/check_views.hxml` checks plugin views listed in `CHECK_PLUGINS` the same way.

For forms, `Pages.redirectsValidation(request)` says whether a failed submission should redirect back to its page, as browsers expect, and `Pages.validationRedirect(request, scope, message, url)` keeps the error and the submitted values for the next page and returns that redirect, or null for a JSON request. `Flash.put` and `Flash.get` keep other values for the next page.

### Upload limits and host locks

A route may lower the request body limit with the `cms.bodyLimit` attribute in bytes, such as `Route.post("/upload/{part}", handler).attribute(BodyLimits.ATTRIBUTE, 1048576)`. The server reads it before it reads the body; the limit applies while the plugin is active.

A plugin that reads installed packages or media files as one consistent snapshot declares `"locks": ["packages", "media"]` in its manifest. The host then holds those locks, in its own order and before the plugin's module lock, while the plugin's routes and scheduled tasks run, so packages cannot be installed and media cannot change meanwhile. Hooks do not take them.

### Installation

A plugin shipped with the application can take part in installation by subscribing to the `installation` hook. While HaxePress is not installed, such plugins are unpacked from their bundled archives and created with `phase: "installation"` in the context; there is no database, administration or scheduler yet. They register routes under `/admin/install` with `Installation.routes(callback)`, behind the installer's access, session and CSRF checks, and serve their `public/` files under `/admin/install/assets/<id>/`. The installation page sends `dispatch("installation.panel", context)` with `data` describing the step (`step`, `driver`, `verified`, `target`); a plugin answers `{"view": "InstallRestore", "props": {...}}` to show one of its templates there, or an empty object.

`Installation.install(request, useVerified, appKey, populate)` installs a site from a source instead of the setup form. Installation is locked while it runs. `populate(database, commit)` fills the empty target database, either the database the visitor verified or a new SQLite file, using the connection configuration it receives, and calls `commit()` once the site's data and files are complete; the configuration is written then, with the source's `APP_KEY`. HaxePress then starts as an installed site. A failure before `commit` leaves nothing behind; after it, `InstallationIncomplete` reports that HaxePress must restart. Once installation completes, the installation instances stop and the installed site starts its plugins as usual. The bundled Backups plugin restores backups this way.

### Host classes

Plugins of every target use the exported API above. A JVM plugin is compiled against the application's sources and may also call its public classes, such as `PackageManifest`, `MediaReferences` or `CmsAccess`, to read site data; it should not depend on internal state such as the package or media locks, the scheduler's tables or the installer's configuration, which the APIs above cover. The Backups plugin (`examples/plugins/site-backup`) is built only on these and has no code in the application. A JVM plugin loads the Haxe standard library from the application, which compiles without dead-code elimination so every member of the classes it includes stays available to plugins.

Put request field rules in the handler's `override validate():Bool`, using `request().validate(...)`. Register the handler instance directly with `Route.post`; calling `execute` from a route callback bypasses the framework's validation lifecycle. The managed plugin route forwards validation while holding the module's lifecycle lock and checks that the installed generation is still active before calling plugin code.

HxWell aborts with HTTP 422 when `validate()` returns false. A handler can implement the shared `hx.press.validation.ValidationResponder` interface to retain an endpoint-specific JSON response or form redirect:

```haxe
import hx.press.validation.ValidationResponder;
import hx.well.handler.AbstractHandler;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.RequestStatic.request;
import hx.well.http.ResponseBuilder;
import hx.well.validator.ValidatorRule;

class ExampleHandler extends AbstractHandler implements ValidationResponder {
    public override function validate():Bool {
        return request().validate(["email" => [Required, String, Email, Max(254)]]);
    }

    public function validationFailed(request:Request):AbstractResponse {
        return ResponseBuilder.asJson({error: "Enter a valid email address."}, 422);
    }

    public function execute(request:Request):AbstractResponse {
        var values = request.only("email");
        var email:String = values.get("email");
        return ResponseBuilder.asJson({email: email});
    }
}
```

Handlers without this interface retain HxWell's standard 422 response. Permission checks, record ownership, uniqueness, optimistic concurrency and other rules that depend on current application state remain in the operation. The core status handler is responsible only for dispatching validation failure responses; it does not run field validation a second time.

## Hooks

| Event               | Data                                                                                     | Result                                             |
| ------------------- | ---------------------------------------------------------------------------------------- | -------------------------------------------------- |
| `site.shared`       | `{ path, content }`, with `content` as `{ id, type }` on published content pages         | Markdown `blocks` with `slot` / `content`          |
| `content.render`    | `{ document, content }`                                                                  | Transformed `content`; stored content is unchanged |
| `content.saving`    | `{ document }`                                                                           | An `error` to reject a manual save                 |
| `content.saved`     | `{ document }`                                                                           | Notification after saving or scheduled publication |
| `dashboard.widgets` | `{ summary }`                                                                            | Markdown blocks with slot `dashboard`              |
| `ui.navigation`     | `{ location, capabilities }`                                                             | Safe internal `items` with label/href/icon         |
| `site.assets`       | Automatically registered for module/styles                                               | Public frontend assets                             |
| `i18n.catalogues`   | Automatically registered for translations                                                | Package-owned catalogues                           |
| `installation`      | Bundled plugins only; `installation.panel` receives `{ step, driver, verified, target }` | A `view` and its `props` for the installation page |

Public slots are `site.top`, `site.before-footer`, `site.footer`, `content.before` and `content.after`. Content uses escaped Markdown/GFM. Transformed content retains the uploaded-image policy. Non-strict public hook failures disable the plugin; validation failures reject the save.

Frontend modules export `activate({ root, settings, path, slot, locale, t })`. Return a cleanup function or export `deactivate(context)`. Navigation/settings changes clean up and remount them. Asset URLs include installed generations; disabled assets return 404. Public settings omit secrets.

## CMS definitions and permissions

Register plugin-owned collections in `onCreate`. The package must already be installed. Existing definitions keep site customizations; disabled, failed or removed owners stop exposing their collections while data remains stored.

```haxe
import hx.press.content.ContentTypes;

ContentTypes.register("catalog", {
    key: "catalog_product",
    name: "Products",
    singular: "Product",
    publicPath: "products",
    dedicatedAccess: true,
    features: ["body", "image", "seo", "revisions", "schedule"],
    fields: [
        {
            key: "price",
            label: "Price",
            kind: "number",
            required: true,
            publicVisible: true,
            inList: true,
            filterable: true
        }
    ]
});
```

Keys are stable lowercase identifiers of at most 32 characters. There are at most 32 fields per type and six listed scalar fields. Text areas and images are detail/editor values. Private fields cannot become public predicates. Draft working copies retain incomplete values; publication validates required fields. The protected owner role grants `*`; other roles contain explicit capability grants. A dedicated collection uses `content.{key}`. Permissions are enforced at request time and applied to active sessions.

```haxe
import hx.press.access.Roles;
import hx.press.navigation.NavigationRegions;

Roles.ensureCapability("catalog.export", "Export catalog", "Catalog", "plugin-catalog");
NavigationRegions.ensure("catalog_links", "Catalog links", 10);
```

Native administration routes can declare `cms.navigation` metadata with `label`, `icon`, `group`, `groupPosition`, `position`, `capability`, optional `exact` and `activePaths`. The host merges these with authorized collection links and the existing `ui.navigation` hook. A plugin page that belongs to the plugin's settings declares `cms.settings` (`{capability}`): the Settings button on the plugin's card opens it in place of the generated settings form. With `cms.settings` alone the page stays out of the menu and Plugins is the current menu entry while it is open; with `cms.navigation` as well it also has its own menu entry. Backup / Restore declares both, so it is listed under Extensions and opened by the Backups card's Settings button. Either attribute's capability also guards the routes below the page for MCP clients. Core route/session/CSRF middleware remains required through `host.admin`.

## Models, migrations and state

Define models inside the plugin's own namespace with native `BaseModel`, rather than editing core model files. The Newsletter source demonstrates a plugin-owned Subscriber model while preserving the original physical table for existing data.

```haxe
package extensions.bookmarks;

import hx.press.plugins.PluginDatabase;
import hx.well.model.BaseModel;
import hx.well.model.BaseModelQuery;

@:table(PluginDatabase.table("bookmarks", "entries"))
class Bookmark extends BaseModel<Bookmark> {
    public static var query:BaseModelQuery<Bookmark>;

    @:primary @:visible @:field public var id:Int;
    @:visible @:field public var title:String;
    @:visible @:field public var content_id:Int;
}
```

Use the same canonical table name in native Schema operations:

```haxe
import hx.press.plugins.PluginDatabase;
import hx.press.plugins.PluginMigration;

var database = new PluginDatabase("bookmarks");
var schema = database.schema();
var tableName = database.tableName("entries");
database.migrate([
    new PluginMigration("001_create_entries", () -> {
        if (!schema.hasTable(tableName)) {
            schema.create(tableName, table -> {
                table.id();
                table.string("title");
                table.integer("content_id");
                table.index(["content_id", "id"]);
                table.foreign("content_id").references("id").on("content_items").cascadeOnDelete();
            });
        }
    })
]);

var rows = Bookmark.query.select(["id", "title", "content_id"])
    .where("content_id", contentId)
    .orderBy("id")
    .limit(20)
    .get();
```

Namespaces are manifest slugs without the installed package's `plugin-` ID prefix. `table(slug, suffix)` creates stable names such as `plugin_bookmarks_entries`, bounds identifiers to 64 characters and shortens long slugs deterministically. Suffixes use at most 32 lowercase letters/digits/underscores. Native plugins have the application's permissions; naming prevents accidental collisions rather than sandboxing trusted code.

Migrations run in supplied order. Successful names are stored once per plugin/connection in `plugin_migrations`. Append names for new schema versions, and keep callbacks idempotent for interrupted upgrades. The runner validates the entire list and loads only its declared names, at most 128 per call. A failed callback is not marked completed and propagates through lifecycle diagnostics. The default does not add a transaction around every migration; pass `true` as the third constructor argument when data/history require one. SQLite column changes may manage their own savepoints/foreign-key handling and should retain the default.

Small JSON state and extra content fields use a scoped value store:

```haxe
var database = new PluginDatabase("bookmarks");
database.put("sync-cursor", {after: 120, complete: false});
var cursor = database.get("sync-cursor", null);

database.put("note", {text: "Review later"}, "content:42");
var note = database.get("note", null, "content:42");
var exists = database.has("note", "content:42");
database.forget("note", "content:42");
```

Lookups include slug/scope/key and read one value. Keys/scopes are bounded to 128 UTF-8 bytes without control characters, and JSON to 65,535 bytes. `has` distinguishes a stored `null`/`false` from a missing key. Native single-row `upsert(data, uniqueBy, updateColumns)` preserves row IDs, and `upsertIncrement(data, uniqueBy, incrementColumns)` adds the supplied values to the stored ones, for counters. Modern SQLite uses UPSERT; older bundled SQLite uses an atomic update/conditional-insert savepoint, including inside explicitly transactional migrations. SQL generation stays inside the framework patch.

A configured alternate connection can be passed to `new PluginDatabase(slug, connectionName)`. Call `initialize()` once before its value store; `migrate()` initializes history/store tables. `schema()` returns the native connection-specific `SchemaBuilder`; models use `@:connection` or configured query parents. Hydrated models retain parent connection/table/primary metadata. Event `database` context exposes `connection`, `namespace` and `tablePrefix`.

Disabling/uninstalling retains plugin tables, values and history for later reinstallation. Data removal is an explicit plugin operation. Use native Cache/Storage for their purposes, cache plain `toObject()` records, select needed fields, filter/count/order in SQL and paginate bounded results. Application/test code contains no raw SQL.

## Themes

Themes declare a stylesheet, a stable lowercase layout identifier and `assets.views`, a folder of Wellout templates (`*.well.html`). Simple is the minimal default. A theme provides any of the standard pages, and the application's own view renders the pages it leaves out:

```ts
['Home', 'ContentIndex', 'ContentDetail', 'Page', 'About', 'NotFound'];
```

Templates are checked when the package is installed, against the same view contract the application uses: the props of each page, the shared values (`site`, `theme`, `navigation`, `i18n`, …), the helpers (`t`, `url`, `themeAsset`, `markdown`, …) and the application's components (`SiteLayout`, `ContentCard`, `Pagination`, `FieldValues`, `ContentFilters`, …). A package whose templates do not check is rejected with the first diagnostic. Theme templates are untrusted: they cannot use islands or raw HTML, and rendering is bounded in output size and component depth. `themeAsset(path)` links the package's `public/` files. Inside the owner-only preview frame, links to public pages keep the preview base, language and customization session. Browser renderers are not supported: a package that declares `assets.renderer` is rejected, and on startup HaxePress replaces such an installed example theme with its Wellout build and removes any other one, activating the built-in theme if it was active.

## Shared translations

Core and packages use English fallback with Turkish included. Declare up to ten JSON catalogues under `translations`. Files are flat key/message objects; plural values contain `one` / `other`. Catalogue limits are 128 KB, 1500 messages, 500 characters per key and 4000 per translation. Named placeholders are substituted once. Messages are plain text.

Namespaces are `plugin-{slug}` and `theme-{slug}`; packages cannot replace another namespace. Theme templates translate with `t(key)`, which checks the theme's catalogue before the core one; native code imports `hx.press.i18n.I18n`, and frontend `activate` receives a package-bound `t`. `I18n.t(key, parameters, namespace, locale)` supports explicit background locale. Public rendering checks the active theme before core messages; administration uses the core namespace. Preference changes use a separate cookie without a public session, and owners configure the default language.

Catalogue caches include package identity, installed generation and locale. Replacement/activation/removal invalidate them. Only active catalogues are public; inactive theme previews can use that theme's translations. Stored authored content is not automatically translated.

## Build and verify

```sh
make build
make test
make test-cppia
make test-php
npm run format:check
```

Build against matching CMS/framework sources and the pinned compiler configuration. The API 4 SDK contains shared source contracts and CPPIA exports; the JVM contract JAR alone does not replace the full compiler/type graph. JAR generation preserves the host graph before thinning classes; CPPIA links host exports externally. PHP uses isolated native type metadata.

SDKs, native plugins and theme ZIPs are generated under `Export/packages/` and published through `public/packages/`. Tests load actual modules on JVM, native C++ and PHP, and use temporary databases with the test-only JVM ORM fixture process. The package in `tests/plugins/database/` demonstrates models, relationships, later migrations and scoped state. Historical API 2 documentation is archived under `docs/history/`.

## Partial and named templates

A theme provides only the templates it implements; the views folder is a set of named templates, not a closed page enum. Administration views cannot be overridden by themes. Missing public templates use the application's standard view.

A theme manifest may declare:

```json
{
  "templates": [{ "name": "ProductDetail", "label": "Product details", "scope": "detail" }],
  "navigation": [{ "key": "catalog_links", "name": "Catalog links", "maxLinks": 10 }]
}
```

Templates accept the same `item`, `collection`, `related`, `items`, filter and cursor props used by the relevant standard view. `<FieldValues>` renders public structured values, and `<ContentFilters>` provides collection-aware search/filter controls. Content links use `item.url` / `item.archiveUrl`; management links use the server's `adminBase`. Previews use the same stored collection paths inside their isolated frame.

SDK artifacts are named from `cms.json` (`cms-plugin-api-4.*`). Use the source SDK and native export metadata with the matching HaxePress checkout and framework compatibility patches. Rebuild older JAR/CPPIA/PHP packages for this exact release; do not mix export metadata from another host.

## Media dependencies

Shared site props use `publisher_name` and `about_site` for optional publisher and site information. `site_logo` is a managed media URL or an empty string. Themes render their text wordmark when it is empty. Saved WebP assets retain managed-media reference tracking. New image uploads accept JPEG, PNG and GIF. [Site identity](SITE-IDENTITY.md)

Plugins that own media data must use the shared [media dependency API](MEDIA-DEPENDENCIES.md). Explicit IDs and soft model columns remain protected after deactivation or uninstall; native incoming foreign keys are detected automatically. `PluginDatabase.put` tracks managed media values. Release a reference only after removing its owning data.
