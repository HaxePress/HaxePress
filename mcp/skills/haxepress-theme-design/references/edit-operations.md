# Editing a draft with operations

Read this before calling `edit_theme_design` (`edit_design` on a theme
connection). One call applies 1–100 operations in order and saves them
together. If any operation fails, nothing is saved and the error says which
rule failed.

```json
{
  "themeId": "theme-harbor",
  "expectedVersion": 7,
  "operations": [/* ... */]
}
```

The result contains the saved `version` (use it for the next call) and
`created`: one `{scope, section, block?}` entry per inserted, duplicated or
added node, in operation order.

## Addressing

`target` and `destination` are `{"scope": "...", "section": "<id>", "block":
"<id>"}`. `scope` is `header`, `footer`, a template name (`Home`,
`ContentIndex`, …, or a custom template) or `@<component-id>`. Leave out
`block` to address the section itself. Get IDs from `inspect_theme_tree` or
`get_theme_section`.

## Actions

| Action      | Fields                                                              | Effect                                                                                                                      |
| ----------- | ------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| `tokens`    | `values`                                                            | Merge into `tokens` (`background`, `text`, `accent`, `font`, `width`, `radius`)                                             |
| `css`       | `text`                                                              | Replace the whole scoped stylesheet                                                                                         |
| `section`   | `target`, `preset?`, `name?`                                        | Add a section after `target.section` (or at the end if it does not exist)                                                   |
| `insert`    | `target`, `preset`, `values?`                                       | Add a block inside `target.block` when it can hold children, otherwise after it; without `block`, at the end of the section |
| `update`    | `target`, `values`                                                  | Set fields of a block or section                                                                                            |
| `style`     | `target`, `values`, `breakpoint?`, `state?`                         | Set CSS declarations (desktop/normal by default); `""` clears one                                                           |
| `move`      | `target`, `destination` (+ `position`: `before`, `after`, `inside`) | Move a block or section                                                                                                     |
| `duplicate` | `target`                                                            | Copy a block or section next to itself with fresh IDs                                                                       |
| `remove`    | `target`                                                            | Delete a block or section                                                                                                   |

`update` accepts, for blocks: `name`, `text`, `href`, `image`, `alt`, `level`,
`tag`, `classes`, `attributes`, `bindings`, `source`, `component`, `slot`,
`condition`, `styles`, `children`; for sections: `name`, `background`,
`color`, `padding`, `columns`, `align`, `width`, `classes`, `styles`. Setting
`styles` or `children` replaces them whole; prefer `style` for a few
declarations.

`target` addresses every action except `tokens` and `css`; `destination`
and its `position` are used only by `move`. A `section` or `insert` operation
without a `target` fails, and a `position` on it is ignored: add the node,
then `move` it.

`classes`, `components`, `feeds` and `templates` cannot be changed with
operations. Use `replace_theme_design` for those, starting from the document
`get_theme_design` returned.

## Presets

- `section` presets: `welcome` (title, message, button), `split` (image and
  text), `highlights` (three cards), `content` (latest content), `callout`
  (one next step), `questions` (questions and answers), `contact` (contact
  details), `empty`, plus `header` and `footer`.
- `insert` presets: any block type (`heading`, `text`, `image`, `button`,
  `container`, `element`, `repeat`, `brand`, `navigation`, `extension`, …) or
  a layout: `layout:row`, `layout:column`, `layout:grid` (three columns that
  collapse), `layout:hero`, `layout:split`, `layout:cards` (a content
  repeater with image, title, excerpt and date already bound), `layout:spacer`.

Presets come with generic placeholder text and styles. Replace the text and
restyle them for the design you planned; leaving "Your heading" or the default
pale blue backgrounds in place is the most common sign of unfinished work.

## Examples

Set the palette and type:

```json
{
  "action": "tokens",
  "values": {
    "background": "#f7f3ec",
    "text": "#211d19",
    "accent": "#a4472a",
    "font": "'DM Sans', Arial, sans-serif",
    "radius": 4
  }
}
```

Add a hero after the first homepage section, then fill it in. `created`
returns the new section and the hero container; the hero's heading, text and
button are children of that container, so read their IDs with
`get_theme_section` before updating them in a second call:

```json
{
  "action": "section",
  "target": { "scope": "Home", "section": "<first-section-id>" },
  "preset": "empty",
  "name": "Hero"
}
```

```json
{
  "action": "insert",
  "target": { "scope": "Home", "section": "<new-section-id>" },
  "preset": "layout:hero"
}
```

Restyle a heading for each device and a button's hover state:

```json
{
  "action": "style",
  "target": { "scope": "Home", "section": "hero", "block": "hero-title" },
  "values": {
    "font-family": "'DM Serif Display', Georgia, serif",
    "font-size": "clamp(44px, 7vw, 96px)",
    "line-height": "1.02",
    "letter-spacing": "-0.02em"
  }
}
```

```json
{
  "action": "style",
  "target": { "scope": "Home", "section": "hero", "block": "hero-title" },
  "breakpoint": "mobile",
  "values": { "font-size": "40px" }
}
```

```json
{
  "action": "style",
  "target": { "scope": "Home", "section": "hero", "block": "hero-cta" },
  "state": "hover",
  "values": { "background": "#211d19", "color": "#f7f3ec" }
}
```

Bind an image to the current item and hide it when there is none:

```json
{
  "action": "update",
  "target": { "scope": "Home", "section": "latest", "block": "card-image" },
  "values": {
    "bindings": { "image": "item.image", "alt": "item.image_alt", "href": "item.url" },
    "condition": { "field": "item.image", "operator": "present", "value": "" }
  }
}
```

A block's `type` cannot change. To turn a plain image into the detail page's
cover, remove it and insert the right block:

```json
{
  "action": "insert",
  "target": { "scope": "ContentDetail", "section": "article" },
  "preset": "content-image"
}
```

Move a block into a container, then remove a section:

```json
{
  "action": "move",
  "target": { "scope": "Home", "section": "intro", "block": "intro-text" },
  "destination": {
    "scope": "Home",
    "section": "intro",
    "block": "intro-column",
    "position": "inside"
  }
}
```

```json
{ "action": "remove", "target": { "scope": "Home", "section": "old-banner" } }
```

## Images

1. Look for a fitting image first: `search_media_for_theme` (the site's
   library) and `search_theme_assets` (images already in the theme). View
   candidates with `read_media_for_theme` / `read_theme_asset_image` before
   choosing them.
2. To add a new one, `upload_theme_image` with the image, check the returned
   preview, then `verify_theme_image` with the upload `id`, its `sha256` and the
   measured `width` and `height`. The result contains the managed URL.
3. Put it on a block with `set_theme_block_image` (`target`, `imageUrl`,
   `alt`) or with an `update` operation setting `image` and `alt`.

CSS backgrounds use the same managed URLs:
`{"background-image": "url('/media/<file>.jpg')", "background-size": "cover"}`.
