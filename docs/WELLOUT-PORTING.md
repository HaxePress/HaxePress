# Writing HaxePress views

HaxePress renders every page with [Wellout](https://github.com/HaxePress/WellOut) templates (`*.well.html`) on the server: the public site, themes, plugin pages and the administration. Inertia and the Node.js renderer are gone. The language reference is `wellout/docs/SPEC.md`. This guide covers the HaxePress conventions, and how pages were ported from the former React ones.

## Goals

- **Same design.** Keep the markup structure and class names of the React page, so `resources/css/*.css` applies unchanged. Check whitespace: JSX drops line breaks between tags, and so does Wellout at the start and end of an element's content. Where React wrote adjacent inline elements with nothing between them, keep them adjacent (`</span><time>`), using Prettier's `><` hugging style.
- **Minimal browser data.** Pages send HTML only. Interactive parts that need state in the browser become islands with typed props.
- **Prepared data.** Compute derived values in Haxe (controllers or a helper), not in templates. Templates read typed fields.

## Files

| What                    | Where                                                                                                                                        |
| ----------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| Page templates          | `resources/views/pages/<Name>.well.html`; the page name is the old Inertia component name, e.g. `pages/Admin/Tags.well.html` is `Admin/Tags` |
| Components and layouts  | `resources/views/components/*.well.html`, `resources/views/layouts/*.well.html`; referenced by file name, e.g. `<Alert>`                     |
| View types              | `src/hx/press/view/types/**/*.hx`, typedefs marked `@:well.view`; they are registered automatically                                          |
| Helpers, filters, roots | `src/hx/press/view/ViewContract.hx` (types) and `ViewHelpers.hx` (implementations), `ViewRoots.hx`                                           |
| Islands                 | `resources/js/islands/<name>.tsx` (or `.ts` without JSX) exporting `mount(element, props, messages)`, registered in `ViewIslands.hx`         |

Controllers and plugins call `View.render("Admin/Tags", props)`. `.status(...)` and `.header(...)` chain on the response. Administration pages are sent with `Cache-Control: private, no-store`.

## Writing a page

```html
<props tags="List<AdminTagView>" notice="String" query="String" pagination="PageLinksView" />
<AdminLayout :title="t('Tags')">
  <div class="admin-page-heading">
    <div><h1>{{ t('Tags') }}</h1></div>
  </div>
  <Alert :message="notice" />
  <Alert error :message="error('tag')" />
  …
</AdminLayout>
```

- `AdminLayout` takes `title` (and optional `description`) and renders the head title, sidebar, breadcrumb, language switcher, AI control and the shared confirmation dialog. Public pages use `SiteLayout` with `<PageHead :title="…" />` inside.
- Every prop is declared with its type. Unknown or nullable values are compile errors; fix the type, test the value with `:if`, or supply a default with `??`.
- Types: `String`, `Int`, `Float`, `Bool`, `Url`, `SafeHtml`, `Any`, `List<T>`, `Map<String, T>`, `T?` and the view types. Declare a typedef for every record shape the page reads; nest typedefs for nested records.

### Roots, helpers and filters

Roots: `site`, `i18n`, `auth` (nullable), `request` (`path`, `url`, `query`), `theme`, `navigation`, `adminSidebar`, `adminLocation`, `errors` (map), `csrfToken`, `translations` (catalogue URL for React islands), `primaryArchive`, `siteUrl`, `pluginRestartRequired`.

Helpers: `t(key, name: value…)`, `can(capability)`, `icon(name)`, `markdown(text)`, `url(path, name: value…)` (adds non-empty values as an encoded query), `query(name)`, `old(field)` (input of a failed submission), `error(field)`, `size(list)`, `any(values)`, `initials(name)`, `year()`, `join(list, separator)`, `active(href, exact, paths)`, `isCurrent(url)`.

Filters: `truncate(n)`, `lower`, `upper`, `default(value)`, `number`, `date`, `color`, `length`, `encode` (like `encodeURIComponent`), `string` (any value as text), `replace(a, b)`, `json`.

`{{ }}` always escapes its value. HTML that trusted code produced, such as `icon('…')` and `markdown(…)`, which return `SafeHtml`, is written with `{!! … !!}`; that form accepts only `SafeHtml` and only in element text, and `{{ }}` on a `SafeHtml` value escapes it with an `escaped-html` warning.

There is no string concatenation: compose text with interpolation (`href="/admin/tags/{{ tag.id }}/edit"`) or `url(...)`. To compare an `Int` with a `String`, use `(value | string)`.

### Forms and actions

- Forms post normally. `method="post"` forms get the CSRF field automatically; `put`, `patch` and `delete` become POST with `_method`.
- Handlers redirect back after success. For validation errors, `AdminController.validationRedirect` flashes `errors` and the submitted input; templates read `error('field')` and `old('field') ?? form.field`. When a handler re-renders the page instead, it passes `errors` in the props and `error()` reads those too.
- Replace client-side state with URLs: an "edit" button becomes a link such as `?edit=12` and the controller fills the form for that record. A "cancel" button becomes a link back.
- Deletions: put the action in its own small form and mark the button `data-well-confirm="{{ t('…') }}"`. `AdminLayout` provides the styled confirmation dialog.
- Client behaviours available without code: `data-well-confirm`, `data-well-busy="{{ t('Saving…') }}"` on submit buttons, `data-well-autosubmit` on selects, `data-well-open="dialog-id"`, `data-well-close`, `data-well-dismiss` on dialogs, `data-well-reveal="input-id"` for passwords. Fragment swaps: mark a region `fragment="name"` and a link or form `swap="name"`; a form swap posts its fields URL-encoded, like the browser. `data-well-autosubmit="button-id"` submits with that button, for its name, value or `formaction`. A submit button linked with `form="id"` takes `data-well-confirm` too.

### Islands

Use an island only for behaviour that cannot be a link, a form or a native element: rich editors, drag and drop, live previews, uploads with progress. React is fine inside islands.

1. Write `resources/js/islands/<name>.tsx`:

   ```tsx
   import MediaPicker from '../components/MediaPicker';
   import { mountReact, type IslandContext } from '../island-react';

   export function mount(element: HTMLElement, props: IslandContext & { … }) {
     return mountReact(element, props, <MediaPicker … />);
   }
   ```

2. Register it in `ViewIslands.islands()` with `react("name", [new FieldInfo("field", TString), …])`.
3. Place it: `<Island name="name" :props="{ translations: translations, locale: i18n.locale, direction: i18n.direction, … }" load="idle">fallback markup</Island>`. The fallback is shown until the island mounts; make it the server-rendered equivalent where possible.

`useTranslation()` works inside islands. `resources/js/page.tsx` provides small `Link`, `router` and `useForm` helpers that use plain links, form posts and `fetch`; prefer a real form submission where one will do.

## Checking

```bash
.tools/haxe/haxe tools/check_views.hxml
```

checks every template against the contract in a few seconds and prints positioned diagnostics. Then compile the server (`python3 tests/build.py`, or a scratch output with the same command) and format with `npx prettier --write resources/views`.
