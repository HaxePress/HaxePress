# HaxePress extension packages, API 4

Owners upload ZIP packages from **Plugins** or **Themes**, review their manifest, install or replace a version, configure settings and activate it. Native code starts on activation/startup, after compatibility checks. Inspecting an archive does not execute its server code.

CMS **2.16.0 / API 4** uses the `hx.press.*` application namespace, `ContentItem` / `content_items` for content storage, and the public renderer pages listed below. Rebuild older native plugins and renderer themes for this exact release. The bundled upgrade retains package settings, activation and the selected theme.

Simple is embedded in the application and is not distributed as a replaceable ZIP. Theme cards use real isolated preview frames; custom `simple` layouts may inherit the application's bundled CSS. See [themes](THEMES.md).

## Package manifest

```json
{
  "apiVersion": 4,
  "cmsVersion": "2.16.0",
  "kind": "plugin",
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

Place `cms-package.json` at the archive root or inside one enclosing folder. Frontend files live in `public/`; optional `assets.module` and `assets.stylesheet` refer to `.js`/`.mjs` and `.css` files there. The normal builder emits all three server targets. JAR and CPPIA remain required; PHP hosts also require `server.php` and its declared classes. `cmsVersion` is an exact release, rather than a version range. API 1/2/3 metadata can be read during upgrades; it does not authorize executing incompatible server modules or renderer themes.

Uploads are capped at 10 MB compressed, 32 MB expanded, 16 MB per file and 256 archive entries. Inspection validates paths, duplicates/case aliases, declared assets, translation files and native artifact structure. Extraction streams bounded entries through Storage. Server modules and browser/SSR code are trusted owner-supplied code with the application's permissions.

Setting kinds are `text`, `textarea`, `boolean`, `number`, `color`, `select` and `secret`. Fields have unique lowercase keys, labels and string defaults, with optional help/required/minimum/maximum/options. Secrets have no default credentials, are encrypted, masked in owner props and omitted from public settings. An empty secret retains its old value; clearing is explicit. Replacement preserves settings whose names and kinds still match.

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

| Target | Module | Loading |
| --- | --- | --- |
| JVM | `server.jar` | A generation-specific class loader sharing the host API |
| C++ | `server.cppia` | Native CPPIA module boot/class resolution with `-D scriptable` |
| PHP | `server.php` | Validated JSON class map and a scoped SPL autoloader |

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

Put request field rules in the handler's `override validate():Bool`, using `request().validate(...)`. Register the handler instance directly with `Route.post`; calling `execute` from a route callback bypasses the framework's validation lifecycle. The managed plugin route forwards validation while holding the module's lifecycle lock and checks that the installed generation is still active before calling plugin code.

HxWell aborts with HTTP 422 when `validate()` returns false. A handler can implement the shared `hx.press.validation.ValidationResponder` interface to retain an endpoint-specific JSON response or Inertia form redirect:

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

| Event | Data | Result |
| --- | --- | --- |
| `site.shared` | `{ path }` | Markdown `blocks` with `slot` / `content` |
| `content.render` | `{ document, content }` | Transformed `content`; stored content is unchanged |
| `content.saving` | `{ document }` | An `error` to reject a manual save |
| `content.saved` | `{ document }` | Notification after saving or scheduled publication |
| `dashboard.widgets` | `{ summary }` | Markdown blocks with slot `dashboard` |
| `ui.navigation` | `{ location, capabilities }` | Safe internal `items` with label/href/icon |
| `site.assets` | Automatically registered for module/styles | Public frontend assets |
| `i18n.catalogues` | Automatically registered for translations | Package-owned catalogues |

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

Native administration routes can declare `cms.navigation` metadata with `label`, `icon`, `group`, `groupPosition`, `position`, `capability`, optional `exact` and `activePaths`. The host merges these with authorized collection links and the existing `ui.navigation` hook. Core route/session/CSRF middleware remains required through `host.admin`.

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

Lookups include slug/scope/key and read one value. Keys/scopes are bounded to 128 UTF-8 bytes without control characters, and JSON to 65,535 bytes. `has` distinguishes a stored `null`/`false` from a missing key. Native single-row `upsert(data, uniqueBy, updateColumns)` preserves row IDs. Modern SQLite uses UPSERT; older bundled SQLite uses an atomic update/conditional-insert savepoint, including inside explicitly transactional migrations. SQL generation stays inside the framework patch.

A configured alternate connection can be passed to `new PluginDatabase(slug, connectionName)`. Call `initialize()` once before its value store; `migrate()` initializes history/store tables. `schema()` returns the native connection-specific `SchemaBuilder`; models use `@:connection` or configured query parents. Hydrated models retain parent connection/table/primary metadata. Event `database` context exposes `connection`, `namespace` and `tablePrefix`.

Disabling/uninstalling retains plugin tables, values and history for later reinstallation. Data removal is an explicit plugin operation. Use native Cache/Storage for their purposes, cache plain `toObject()` records, select needed fields, filter/count/order in SQL and paginate bounded results. Application/test code contains no raw SQL.

## Themes

Themes declare a stylesheet and a stable lowercase layout identifier. Simple is the minimal default. Renderer themes declare `assets.renderer` and export `createTheme(runtime)`. The following standard pages are available as fallback views:

```ts
['Home', 'ContentIndex', 'ContentDetail', 'Page', 'About', 'NotFound']
```

The runtime injects the host React/Inertia instance, translated UI primitives, navigation helpers and `asset(path)`. Bundle package-owned components, not another React runtime. Public props use `ContentItem`, `items`, `item` and generic content/page routes. `Link` and `useSiteHref()` keep preview navigation in the selected owner-only frame, including locale/query parameters. The outer preview toolbar and desktop/tablet/mobile controls remain isolated from theme CSS.

The browser imports the generation-specific module URL. Node SSR imports that installed module from `CMS_STORAGE_PATH`. The launcher and test runners set it to the same storage root as the JVM. Theme code runs in both browser and SSR contexts with the normal active-theme/owner checks.

## Shared translations

Core and packages use English fallback with Turkish included. Declare up to ten JSON catalogues under `translations`. Files are flat key/message objects; plural values contain `one` / `other`. Catalogue limits are 128 KB, 1500 messages, 500 characters per key and 4000 per translation. Named placeholders are substituted once. Messages are plain text.

Namespaces are `plugin-{slug}` and `theme-{slug}`; packages cannot replace another namespace. React uses `useTranslation(namespace)`, native code imports `hx.press.i18n.I18n`, and frontend `activate` receives a package-bound `t`. `I18n.t(key, parameters, namespace, locale)` supports explicit background locale. Public rendering checks the active theme before core messages; administration uses the core namespace. Preference changes use a separate cookie without a public session, and owners configure the default language.

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

A renderer can return only the templates it implements. `pages` is a name-to-component map, not a closed page enum. Administration components cannot be overridden by themes. Missing public templates use the controller-provided standard view; the CMS uses the shared Vite entry rather than requiring a source file per runtime template name.

A theme manifest may declare:

```json
{
  "templates": [
    { "name": "ProductDetail", "label": "Product details", "scope": "detail" }
  ],
  "navigation": [
    { "key": "catalog_links", "name": "Catalog links", "maxLinks": 10 }
  ]
}
```

Templates accept the same `item`, `collection`, `related`, `items`, filter and cursor props used by the relevant standard view. `runtime.FieldValues` renders public structured values, and `runtime.ContentFilters` provides collection-aware search/filter controls. Content links use `item.url` / `item.archiveUrl`; management links use the server's `adminBase`. Previews use the same stored collection paths inside their isolated frame.

SDK artifacts are named from `cms.json` (`cms-plugin-api-4.*`). Use the source SDK and native export metadata with the matching HaxePress checkout and framework compatibility patches. Rebuild older JAR/CPPIA/PHP packages for this exact release; do not mix export metadata from another host.

## Media dependencies

Shared site props use `publisher_name` and `about_site` for optional publisher and site information. `site_logo` is a managed media URL or an empty string. Themes render their text wordmark when it is empty. Saved WebP assets retain managed-media reference tracking. New image uploads accept JPEG, PNG and GIF. [Site identity](SITE-IDENTITY.md)

Plugins that own media data must use the shared [media dependency API](MEDIA-DEPENDENCIES.md). Explicit IDs and soft model columns remain protected after deactivation or uninstall; native incoming foreign keys are detected automatically. `PluginDatabase.put` tracks managed media values. Release a reference only after removing its owning data.
