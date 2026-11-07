# The theme document (schema 2)

Read this when you write or replace a whole document, bind content, or a save
is rejected. `get_theme_design_guide` returns the same limits in JSON and is
the source of truth if the two ever differ.

## Contents

1. Top level
2. Sections
3. Blocks
4. Styles, classes and CSS
5. Content: bindings, repeaters, feeds, conditions
6. Templates and components
7. Limits
8. Rejected saves and their fixes

## 1. Top level

```json
{
  "schema": 2,
  "tokens": {
    "background": "#fbfaf7",
    "text": "#1f2421",
    "accent": "#9a3b1d",
    "font": "'DM Sans', Arial, sans-serif",
    "width": 1120,
    "radius": 8
  },
  "header": [/* sections */],
  "footer": [/* sections */],
  "templates": {
    "Home": [],
    "ContentIndex": [],
    "ContentDetail": [],
    "Page": [],
    "About": [],
    "NotFound": []
  },
  "templateMeta": {},
  "components": {},
  "classes": {},
  "feeds": [],
  "css": ""
}
```

- `tokens.width` is the content width in pixels (240–3840); `radius` is the
  default corner radius in pixels (0–200). Colors are hex.
- All six core templates must exist. `header` and `footer` wrap every public
  page.

## 2. Sections

A section is a horizontal band of a page.

```json
{
  "id": "home-hero",
  "name": "Introduction",
  "background": "#1f2421",
  "color": "#fbfaf7",
  "padding": 96,
  "columns": 1,
  "align": "left",
  "width": "wide",
  "blocks": [],
  "styles": {},
  "classes": []
}
```

- `padding` is the vertical padding in pixels (0–2000). Every section also gets
  28px of side padding, 20px on phones.
- `columns` lays the section's blocks out in equal grid columns (up to 12 are
  drawn). They collapse to two columns below 800px and to one below 580px.
  Use `columns: 1` and a grid `container` when columns need different widths.
- `width`: `content` follows `tokens.width`, `wide` is 1440px, `full` spans the
  window. `align` sets the text alignment. `background` and `color` may be
  empty to inherit the tokens.

## 3. Blocks

Every block has `id`, `type`, `text`, `href`, `image`, `alt`, `level`, and
optionally `name`, `tag`, `children`, `styles`, `classes`, `attributes`,
`bindings`, `source`, `component`, `slot`, `condition`, `newTab`. IDs are
unique ASCII strings of up to 40 characters across the whole document.

`newTab: true` opens the link of a `button`, a linked `heading` or `image`, or
an `element` with `tag: "a"` in a new tab, with `rel="noopener noreferrer"`.
Use it for links that leave the site, such as documentation or a shop, and
leave it out elsewhere. Any other block with `newTab` is rejected.

| Type                                                                | What it renders                        | Notes                                                                        |
| ------------------------------------------------------------------- | -------------------------------------- | ---------------------------------------------------------------------------- |
| `container`                                                         | A `div` that holds children            | Flex or grid layouts                                                         |
| `element`                                                           | Any allowed HTML tag (`tag`)           | Semantic markup, lists, tables, inline SVG; only non-text tags take children |
| `heading`                                                           | `h1`–`h6` (`level`)                    | One `level: 1` per page template                                             |
| `text`                                                              | A paragraph                            |                                                                              |
| `image`                                                             | An image                               | `image` must be managed; always write `alt`                                  |
| `button`                                                            | A link styled as a button              | `href` required                                                              |
| `spacer`, `divider`                                                 | Space, a rule                          |                                                                              |
| `brand`                                                             | Site logo and name from settings       | Use instead of typing the name                                               |
| `navigation`                                                        | The site menu from settings            |                                                                              |
| `repeat`                                                            | Children repeated per content item     | See section 5                                                                |
| `component`                                                         | An instance of `components[component]` |                                                                              |
| `extension`                                                         | A plugin area named by `slot`          | Lets plugins (newsletter forms…) appear                                      |
| `pagination`                                                        | Archive page links                     | ContentIndex                                                                 |
| `search`                                                            | Content filters and search             | ContentIndex                                                                 |
| `content-list`                                                      | A ready-made list of content cards     | Quick but less designable than `repeat`                                      |
| `content-title`, `content-excerpt`, `content-image`, `content-body` | The current item                       | ContentDetail, Page, About; `content-body` also shows custom fields          |
| `site-description`                                                  | The site description setting           |                                                                              |

Only `container`, `repeat` and non-text `element` tags may have children.
`element` tags include `section`, `article`, `aside`, `header`, `footer`,
`nav`, `main`, `figure`, `figcaption`, headings, `p`, `span`, `a`, `strong`,
`em`, `small`, `blockquote`, `ul`, `ol`, `li`, `dl`/`dt`/`dd`,
`details`/`summary`, `time`, `form` and its controls, `table` parts, `pre`,
`code`, and SVG shapes.

Attributes: a fixed safe list (`id`, `title`, `role`, `name`, `type`,
`value`, `placeholder`, `for`, `method`, `action`, `target`, `rel`,
`datetime`, `colspan`, `open`) plus any `aria-*` and `data-*` attribute, at
most 32 per element. **Only `element` blocks take attributes**; a save with
attributes on any other block type is rejected. To open a link in a new tab,
set the block's `newTab` instead of `target` and `rel`. Event handlers, `style`,
`src` and `href` are not attributes: use `styles`, the `image` field and the
block's `href` field.

Inline SVG is built from `element` blocks (`svg`, `path`, `g`, `circle`,
`rect`, `line`, `polyline`, `polygon`, `ellipse`, gradients, `clipPath`,
`mask`, `use`, `text`). Its attributes are limited to geometry and paint:
`viewBox`, `d`, `points`, `cx`, `cy`, `r`, `rx`, `ry`, `x`, `y`, `x1`, `x2`,
`y1`, `y2`, `width`, `height`, `transform`, `offset`, `fill`, `stroke`,
`stroke-width`, `stop-color`, `clip-path`, `xmlns`. Everything else, such as
`stroke-linecap`, `stroke-linejoin`, `stroke-opacity`, `opacity` or `href`,
is rejected; set those as CSS properties in the element's `styles`.

## 4. Styles, classes and CSS

```json
"styles": {
  "desktop": { "normal": { "display": "grid", "grid-template-columns": "2fr 1fr", "gap": "48px" } },
  "tablet":  { "normal": { "gap": "32px" } },
  "mobile":  { "normal": { "grid-template-columns": "minmax(0, 1fr)" }, "hover": {} }
}
```

- Breakpoints are `desktop` (base), `tablet` and `mobile`; states are
  `normal`, `hover` and `focus`. Tablet overrides desktop and mobile overrides
  both, so write only what changes. An empty string value inherits.
- Values are plain CSS strings without `;`, `{` or `}`. At most 100
  declarations per state.
- `classes` is a map from a lowercase-hyphenated name to the same responsive
  style shape. Add a class name to a block's or section's `classes` list to
  apply it. Use classes for anything that repeats: card, eyebrow-free section
  title, button variants.
- `css` is a stylesheet wrapped in `@scope (.hp-design)`. Use it for things
  styles cannot express: `@media` queries, `:hover` on descendants,
  `::before`, `@keyframes`, CSS custom properties. No `@import`, no
  `expression()`, no HTML. `url()` may point only at managed media,
  `/theme-assets/<themeId>/…`, `/fonts/…`, `/images/…` or `/build/assets/…`.
- Fonts: `'DM Sans'` and `'DM Serif Display'` are loaded on every public page.
  Anything else must be a system font stack.

## 5. Content: bindings, repeaters, feeds, conditions

`bindings` maps a block field (`text`, `href`, `image`, `alt`, `value`,
`datetime`) to a path: a prefix and one field from this table, or a custom
field as `item.fields.<key>`. `condition.field` takes the same paths.

| Prefix        | Fields                                                                                                                                                          |
| ------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `item.`       | `title`, `url`, `image`, `image_alt`, `excerpt`, `category`, `publishedLabel`, `published_at`, `updatedLabel`, `readMinutes`, `typeLabel`, `archiveUrl`, `slug` |
| `site.`       | `site_name`, `site_logo`, `description`, `about_site`, `publisher_name`, `locale`                                                                               |
| `collection.` | `name`, `singular`, `description`, `publicBase`                                                                                                                 |
| `page.`       | `count`, `resultCount`, `query`, `category`, `archiveUrl`                                                                                                       |

`item.fields.<key>` reads a collection's custom field by its key (lowercase
letters, digits and `_`), such as `item.fields.price`. Lists and feeds carry
only the public fields marked to show in lists; detail pages carry every
public field; private fields never render. A field the page does not carry
renders nothing. Any other path, such as `item.fields.price.amount` or
`site.links.home`, is rejected. `content-body` also shows the custom fields on
detail pages.

A `repeat` block renders its children once per item:

```json
{
  "id": "latest",
  "type": "repeat",
  "source": "feed:latest",
  "styles": {
    "desktop": {
      "normal": {
        "display": "grid",
        "grid-template-columns": "repeat(3, minmax(0, 1fr))",
        "gap": "32px"
      }
    },
    "mobile": { "normal": { "grid-template-columns": "minmax(0, 1fr)" } }
  },
  "children": [
    {
      "id": "latest-card",
      "type": "container",
      "classes": ["card"],
      "children": [
        {
          "id": "latest-image",
          "type": "image",
          "bindings": { "image": "item.image", "alt": "item.image_alt", "href": "item.url" },
          "condition": { "field": "item.image", "operator": "present", "value": "" }
        },
        {
          "id": "latest-title",
          "type": "heading",
          "level": 3,
          "bindings": { "text": "item.title", "href": "item.url" }
        },
        {
          "id": "latest-date",
          "type": "element",
          "tag": "time",
          "bindings": { "text": "item.publishedLabel", "datetime": "item.published_at" }
        }
      ]
    }
  ]
}
```

- `source` is `page.items` (the archive's own items, on ContentIndex and the
  homepage when it lists content), `page.related` (ContentDetail) or
  `feed:<id>`. Every block carries a `source` field; leave it out or set
  `page.items` on blocks that are not repeaters, because an empty string is
  rejected.
- `feeds` define bounded queries for anywhere else:
  `{"id": "latest", "name": "Latest posts", "collection": "entry", "limit": 6,
"category": "", "tag": "", "query": "", "order": "published_at",
"direction": "DESC"}`. `order` is exactly `published_at`, `title` or `id`;
  `direction` is exactly `ASC` or `DESC`. At most 8 feeds, 24 items each. Take
  the collection key from `collections` in `get_theme_design`.
- `condition` shows a block only when `field` is `present`, `empty` or
  `equals` a value. Use it so cards without images do not show a broken frame.

## 6. Templates and components

- Extra page layouts go in `templates` under a new name, with
  `templateMeta[name] = {"label": "Landing page", "fallback": "Page"}`.
  People assign them to pages or collections in the CMS; creating one does not
  create a URL.
- `components[id] = {"name": "Newsletter band", "sections": [...]}` defines
  reusable content; a `component` block with `"component": "<id>"` renders it.
  A change to the definition updates every instance. Components cannot contain
  themselves.

## 7. Limits

1 MB per document, 2048 nodes, 16 nesting levels, 256 blocks per list,
128 sections per scope, 100 declarations per style state, 32 attributes per
element, 64 classes, 32 components, 32 templates, 8 feeds of up to 24 items,
128 managed images per design, 100 operations per `edit_theme_design` call.
A template may expand to at most 20,000 elements once repeaters and
components are counted.

## 8. Rejected saves and their fixes

| Message contains                                                           | Fix                                                                                                                                                          |
| -------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `Keep every core CMS template`                                             | Restore the missing template key, even as an empty list                                                                                                      |
| `unique identifier`                                                        | Two nodes share an ID, or an ID is missing; IDs are document-wide                                                                                            |
| `cannot contain children` / `Only containers, HTML elements and repeaters` | Move the children into a `container` or a non-text `element`                                                                                                 |
| `public CMS field for this binding` / `bindable property`                  | Use a path and field from section 5, or `item.fields.<key>`; nothing deeper                                                                                  |
| `missing content source`                                                   | Add the feed to `feeds`, or use `page.items`                                                                                                                 |
| `uploaded images from this theme or the media library`                     | Use a URL from `search_media_for_theme`, `search_theme_assets` or `verify_theme_image`                                                                       |
| `CSS resources must use the media library or application assets`           | Replace remote `url()` values                                                                                                                                |
| `without imports, executable values or HTML markup`                        | Remove `@import`, `expression()`, `javascript:` or tags from `css`                                                                                           |
| `without a rule or declaration separator`                                  | A style value contains `;`, `{` or `}`; split it into separate properties                                                                                    |
| `valid CSS property`                                                       | Use a real property name in lowercase, such as `background-color`                                                                                            |
| `font family name or font stack`                                           | Use comma-separated family names with no empty entry, close every quote, and quote a name that starts with a digit; no sizes or weights                      |
| `internal path or a valid web, email or phone link`                        | Use `/path`, `https://…`, `mailto:` or `tel:`                                                                                                                |
| `Forms must submit to a CMS route`                                         | Point `action` at a site path such as `/search`                                                                                                              |
| `HTML attribute is not supported`                                          | Use `styles` instead of `style` and SVG paint extras, `image` instead of `src`, the block's `href` field instead of an `href` attribute; drop event handlers |
| `Only HTML element blocks take attributes`                                 | Remove `attributes` from the named block, or rebuild it as an `element` with the same tag                                                                    |
| `current-page list or a named content source`                              | A block has `source: ""`; remove the field or set `page.items`                                                                                               |
| `supported value for order` / `direction`                                  | Use `published_at`, `title` or `id`, and `ASC` or `DESC` in capitals                                                                                         |
| `node document limit` / `nesting limit` / `repeated or reusable elements`  | Simplify: fewer wrappers, smaller feeds, components instead of copies                                                                                        |
| `The saved design changed`                                                 | Read the design again and reapply your change to the new version                                                                                             |
