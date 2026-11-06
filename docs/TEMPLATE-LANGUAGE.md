# Wellout in HaxePress

Status: implemented, 2026-11-06. Sections 2–5 record the design as planned; the phase table in section 6 records what was done.

HaxePress replaced Inertia page rendering and the Node.js SSR renderer with Wellout, for public themes, plugin views and the administration panel. The language itself is specified in the Wellout repository (`wellout/docs/SPEC.md`); templates use the `.well.html` extension. This document covers what HaxePress provides as the host, the migration plan and the measurements behind the decision.

## 1. Background

Measured on 2026-11-06 against the local JVM server with demo content. The appendix has the method and full numbers.

- The homepage HTML is 312 KB; 81% of it is the escaped Inertia `data-page` attribute. Page content is about 3% of the props. Most of the rest is the full core translation catalogue (89 KB, including administration strings) and the complete published design document (70 KB, all six templates).
- Before phase 0, public pages preloaded about 548 KB (164 KB gzip) of administration and builder JavaScript.
- A homepage request allocated about 9.5 MB on the long-running server. In a controlled comparison on the current tree it allocated 28.3 MB before phase 0 and 15.5 MB after it. About 75% of the remainder comes from the Inertia SSR pipeline.
- `haxe.Template` (mtt) does not escape output and prints missing values as `null`. On the JVM it throws `ClassCastException` for `::if::` over strings and dispatches macros only on class instances.

## 2. HaxePress as the Wellout host

### 2.1 View types and contexts

View types are declared with `@:well.*` metadata (see `ContentSummary` in the Wellout specification). Secret package settings never appear in a view type.

| Template kind         | Available roots                                                                                       |
| --------------------- | ----------------------------------------------------------------------------------------------------- |
| Public theme template | Implicit roots, route props (`item`, `items`, `collection`, `pagination`, `tag`, `query`) and sources |
| Plugin view           | As public templates, plus the plugin's own view types                                                 |
| Administration        | Administration view types, `can`, `old`, `error` and flash messages                                   |

Implicit roots are `site`, `theme`, `locale`, `request`, `csrf` and `nonce`. Theme contexts follow a versioned contract (`"api": 3` in `cms-package.json`).

### 2.2 Source functions

- **Functions:** `entries(…)`, `related(item, …)`, `count(…)` and `navigation(region: …)`, implemented with model and query builders following the query rules in `AGENTS.md`.
- **Bounds:** theme sources return at most 24 records, archives use cursor pagination, and sort keys come from an allowlist.

### 2.3 Helpers and lookup chain

- **Helpers:** `t`, `route`, `asset`, `can`, `old` and `error`.
- **Component lookup:** the active theme, its parent theme, plugin components namespaced as `<newsletter:Signup>`, then core components.

### 2.4 Theme policy

- **Elements:** theme templates use the tag allowlist from `ThemeDesignValidator` and the Wellout reference attribute policy.
- **Images:** image attributes accept only managed media URLs and the theme's own asset URLs.
- **Limits:** the builder's existing limits apply (1 MB, 2048 nodes, 16 levels, 20,000 expanded elements per template), together with the Wellout default render budgets.
- **Failures:** when a theme fails or exceeds a budget, the core template renders instead.
- **CSS:** theme CSS comes from the theme stylesheet and the compiled builder styles.

### 2.5 Builder

The builder's document format becomes the Wellout IR (builder schema 3). Schema 2 documents are upgraded on read, as schema 1 documents are today. Today's `feeds` become document sources.

## 3. Runtime in HaxePress

### 3.1 Cache tier (phase 0, implemented)

`ContentCache` now has three in-memory layers in front of `FileSystemCacheStore`:

- **Key prefix:** the database part of each key is computed once per `DB_PATH`.
- **Request revisions:** revision tokens are read once per HTTP request. WebSocket sessions keep their upgrade request, so they always read the stored token.
- **Hot set:** fourteen allowlisted operations are kept in a 4 MB set, with at most 256 KB per entry and a copy on every read. These are settings, active theme, packages, plugin events, theme design records, translations, navigation, category navigation, content types and active plugin directories.
  - An entry lives as long as the file cache entry when it was recomputed, and at most 60 seconds when it was read from a file.
  - Search, list and editor results stay in the file cache only.

`ThemeDesignData` also keeps parsed design documents and parses again only when the stored JSON changes.

### 3.2 Response path (implemented)

Before this change, every response body was encoded with `Bytes.ofString`, copied into a 32 KB `readUpTo` buffer and copied again with `sub`. Bodies over 32 KB were copied again for each slice. Two maintained patches and one provider change this:

- **`patches/hxwell-response-slices.patch`:**
  - adds `ResponseSlice` (bytes, length and a one-time `release`) and `Response.slice()`,
  - adds a `Response.textEncoder` hook,
  - makes `StringResponse` (and so Inertia pages) and `JsonResponse` use the hook.
- **`patches/hxwell-crossbyte-response-slices.patch`:**
  - when a response has a slice, the driver skips `toInput()`, `readUpTo` and `sub`,
  - wraps the buffer in a `ByteArray` without copying and hands it to `respondBytes`,
  - releases the slice right after that call. Crossbyte copies caller-owned bytes before `respondBytes` returns, which makes this safe. The slice is also released when the response can no longer be sent.
- **`ResponseEncodingProvider`:** installs `ResponseBodies.encode`, which writes text bodies into a pooled Wellout `ByteWriter` in one UTF-8 pass. The pool keeps at most 16 writers and drops writers above 1 MB.

Drivers without slice support, and responses that use HxWell's own deflate encoder, keep the previous path. `Response.after` would be too early for releasing a pooled buffer, because the Crossbyte runtime may still be writing.

### 3.3 Full-page cache (planned)

Anonymous `GET` responses are cached as final bytes, together with compressed variants. The key combines the method, URL, locale, theme version, fragment and the content, settings, navigation and structure revisions. Requests with a session cookie or authorization bypass the cache. A hit performs no rendering.

### 3.4 Targets

| Measure                                         | Target                                     |
| ----------------------------------------------- | ------------------------------------------ |
| Homepage request, JVM heap allocation           | ≤ 64 KB, excluding database driver strings |
| Public page JavaScript without swaps or islands | 0 bytes                                    |

## 4. Administration

- Administration pages are core templates (backend A). Tables, filters and pagination use fragments; forms use actions.
- Validation errors, old input and flash messages are rendered on the server.
- Templates use `can()` only for presentation. Authorization is enforced in routes and loaders.

| Pages                                                                                                                                                                      | Approach                                                                                         |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| Account, Activity, Categories, Collections, Content, ContentTypeEditor, Dashboard, ExtensionSettings, Forbidden, Install, Login, PluginPage, RoleEditor, Roles, Tags, Team | Templates, fragments and actions                                                                 |
| Extensions, Media, Navigation, Settings, ThemeCreate, ThemePreview                                                                                                         | Templates with small islands: uploads with browser hash verification, sorting, the preview frame |
| Editor, ThemeBuilder                                                                                                                                                       | React islands inside a template shell                                                            |

New administration pages added before the migration, such as Backups, join the first group unless they need browser-only work.

## 5. Themes

### 5.1 Existing themes

| Theme                          | Kind                                                | What it uses                                                                                                                                                                           |
| ------------------------------ | --------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Simple                         | Built-in React pages (`resources/js/pages`)         | Six pages, a layout and core components                                                                                                                                                |
| Fieldnotes                     | API 4 ZIP with a React renderer (`examples/themes`) | Layout, six pages and a card component (about 700 lines). Interaction: a menu toggle, a search dialog with a Cmd/Ctrl+K shortcut, and a share button with a short confirmation message |
| Gallery, Notebook              | API 4 ZIPs that reuse the Fieldnotes renderer       | About 1 KB of CSS each and the same seven settings fields                                                                                                                              |
| Builder themes (a real export) | Visual builder export (schema 2 design document)    | Six templates and 120 nodes: elements, containers, buttons, headings, text, images, inline SVG, CMS blocks, one repeater and one presence condition                                    |

All themes read the same data: site identity, collection details, content records and theme settings.

### 5.2 Migration per theme kind

- **Builder themes:** migrate automatically. The schema 2 upgrade turns repeaters into `:for`, conditions into `:if`, bindings into interpolation and CMS blocks into core components. Styles compile to the versioned stylesheet. A real builder export served as the conformance fixture for this upgrade.
- **Simple:** rewritten once as core Wellout templates (backend A).
- **Fieldnotes:** ported once to `*.well.html`. The interaction maps as follows:
  - the menu toggle becomes `<details>` and needs no JavaScript,
  - the search form already works as a plain GET form, and the dialog uses `<dialog>` plus a small keyboard-shortcut island,
  - the share button becomes an island loaded on interaction.

  Gallery and Notebook keep their CSS and settings and use the ported templates, so one port covers three themes.

- **Third-party API 2 and 4 renderer themes:** cannot be converted automatically, because they contain arbitrary React code. Renderer support is removed: such packages are rejected at upload and removed from sites on startup, with the built-in theme taking over; authors port them to `*.well.html` views as Fieldnotes was.

### 5.3 Core component library

Code themes and builder blocks use one set of server-rendered components:

| Today (React runtime or builder block)                                 | Wellout core component or helper                                               |
| ---------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| `Link`, `useSiteHref`                                                  | Plain `<a href="/…">`; the link mapper keeps preview links inside the preview  |
| `Icon`                                                                 | `<Icon name="…" />`, rendered as inline SVG                                    |
| `PageHead`, `Head`                                                     | `<Head>` with `<title>`, `<meta>` and `<link>`                                 |
| `SiteNavigation`, builder `navigation`                                 | `<Navigation region="header" />`                                               |
| `ExtensionSlot`, `PublicExtensions`                                    | `<ExtensionSlot name="site.top" />`, rendered from plugin blocks on the server |
| `FieldValues`                                                          | `<FieldValues :item="item" />`                                                 |
| `ContentFilters`                                                       | `<ContentFilters :collection="collection" />` as a GET form                    |
| `Pagination`                                                           | `<Pagination :page="pagination" />`, with `swap` support                       |
| `LanguageSwitcher`                                                     | `<LanguageSwitcher />` as a form posting to `/locale`                          |
| `Markdown`                                                             | `{{ item.content }}` as `SafeHtml` from the server's CommonMark renderer       |
| Builder `brand`, `site-description`                                    | `<Brand />`, `{{ site.description }}`                                          |
| Builder `content-title`, `-excerpt`, `-image`, `-body`, `content-list` | Bindings on `item` and `<ContentList :items="items" />`                        |

Theme settings stay typed. A colour becomes a CSS variable through a typed filter, for example `style="--accent: {{ theme.settings.accent | color }}"`, and a select becomes a class, for example `class="type-{{ theme.settings.typeface }}"`.

### 5.4 Packages

- **Manifest:** `cms-package.json` declares `"api": 3`, templates (name, label and scope), components, islands, assets, settings fields and an optional `parent`.
- **Directories:** `templates/`, `components/`, `islands/`, `assets/` and `lang/`, with `*.well.html` templates.
- **Upload:** upload inspection compiles and validates every template. Errors block installation and are shown with their positions.
- **Activation:** activating or publishing a theme switches the compiled version atomically.
- **Builder themes:** builder themes store IR version 3 and export as packages with the same layout.
- **Settings:** theme settings are typed from their field kinds and readable as `theme.settings.*`. Secret fields are excluded.
- **API 2 themes:** themes that declare a JavaScript renderer are rejected with a migration message and removed on startup.

## 6. Migration plan

Wellout is developed in its own repository and pinned by commit in `dependencies.lock.json`; `WELLOUT_PATH` points setup at a local checkout.

| Phase | Work                                                                             | Status or done when                                                        |
| ----- | -------------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| 0     | Lazy administration chunks, `ContentCache` memory tiers, parsed design documents | Done: 28.3 → 15.5 MB per homepage request; full suite passes               |
| 0     | Allowlist content projections                                                    | Pending                                                                    |
| 1     | `ByteWriter` and pool (in Wellout), byte-slice response patches                  | Done: 0 bytes per steady-state render; 15.6 → 14.0 MB per homepage request |
| 1     | Schema macro, full-page cache                                                    | Pending                                                                    |
| 2     | Front end, diagnostics, IR, conformance suite skeleton                           | Parser and type-checker tests pass; schema 2 documents upgrade             |
| 3     | Backend A; first administration pages (Login, Account, Activity, Dashboard)      | Done                                                                       |
| 4     | Backends B and C; Simple theme and public templates; builder canvas on backend C | Done with one backend (B, the op tree); builder themes compile to views    |
| 5     | Runtime script, fragments, actions and islands; remaining administration pages   | Done: all administration pages; Editor and ThemeBuilder run as islands     |
| 6     | Remove Inertia and the Node.js SSR renderer; retire API 2 renderer themes        | Done: no `data-page` output; pages render without Node.js                  |

## 7. Open questions

1. L1 invalidation when several JVMs share one deployment. The current tier relies on revision tokens read once per request.
2. Whether the site needs the props leak (administration strings, full design document) closed before Wellout replaces public pages.

## Appendix: Measurements

All measurements were taken on 2026-11-06 on macOS with Java 25 and Haxe 4.3.7, with the demo seed content.

### Homepage payload

| Item                               | Size                                    |
| ---------------------------------- | --------------------------------------- |
| HTML document                      | 312 KB                                  |
| Escaped `data-page` attribute      | 254 KB (81% of the document)            |
| Props JSON                         | 158 KB                                  |
| `i18n` prop                        | 90.6 KB (core catalogue: 1,572 keys)    |
| `theme` prop                       | 70.6 KB (design templates: 56.6 KB)     |
| Page content (`items`, `featured`) | 5.3 KB                                  |
| JavaScript before phase 0          | 1.19 MB raw, 376 KB gzip, in 51 modules |
| JavaScript after phase 0           | 655 KB raw, 217 KB gzip, in 20 modules  |

### Request allocation

The controlled comparison built two jars from one source snapshot, started each in a fresh JVM with a copy of the site's storage, sent 1,230 warm-up requests and recorded 200 homepage requests with JFR. Totals come from `jdk.ThreadAllocationStatistics`.

| Build          | Allocation per request |
| -------------- | ---------------------- |
| Before phase 0 | 28.3 MB                |
| After phase 0  | 15.5 MB                |

Where the remaining 15.5 MB goes, from `jdk.ObjectAllocationInNewTLAB` and `jdk.ObjectAllocationOutsideTLAB` events (these cover 15.6 MB per request):

| Stage                                       | Per request |
| ------------------------------------------- | ----------- |
| SSR request to Node.js and response reading | 3.58 MB     |
| Root template (mtt)                         | 2.57 MB     |
| SSR response JSON parsing                   | 2.34 MB     |
| HTML-escaping the page JSON                 | 1.81 MB     |
| Driver body copies and slices               | 1.50 MB     |
| Page JSON (`Json.stringify`)                | 1.41 MB     |
| String to UTF-8 bytes                       | 1.24 MB     |
| Theme and props preparation                 | 0.69 MB     |
| Asset version per request                   | 0.22 MB     |
| `ContentCache`                              | 0.13 MB     |

The byte-slice response path was measured the same way, twice, with and without `ResponseEncodingProvider` on one source snapshot:

| Response path                  | Allocation per request (two runs) |
| ------------------------------ | --------------------------------- |
| `toInput()`, `readUpTo`, `sub` | 15.64 MB, 15.63 MB                |
| Pooled UTF-8 slice             | 13.96 MB, 13.95 MB                |

In the TLAB events, the string-to-bytes stage fell from 1.2 MB to 0 and driver copies from 1.6 MB to 0.07 MB. These events credit a whole thread-local buffer to the allocation that triggered it, so other stages appeared to grow when the large copies disappeared. The exact counters show a net saving of 1.68 MB per request.

The long-running server measured 9.5 MB per request (2.05 GB and 32 collections over 200 requests). That figure is not comparable with the table above: it ran an older jar with a fully warmed JIT.

### After the migration

Measured on 2026-11-06 after phase 6, in a fresh JVM on a scratch copy of the site with the builder theme active: 1,200 warm-up requests, then 200 homepage requests recorded with JFR; the total comes from `jdk.ThreadAllocationStatistics`. It is a single run of the final jar, not an A/B pair on one snapshot like the tables above, so read the comparison as an order of magnitude.

| Item                          | Before (Inertia and SSR) | After (Wellout) |
| ----------------------------- | ------------------------ | --------------- |
| Homepage HTML                 | 312 KB                   | 20.4 KB         |
| Allocation per request        | 13.96 MB                 | 0.83 MB         |
| Node.js process for rendering | Required                 | None            |

Rendering itself allocates nothing in the steady state (Wellout's allocation test); the remaining 0.83 MB is spent in the request pipeline, data access and caches.

