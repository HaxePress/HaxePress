---
name: haxepress-theme-design
description: Design, build or restyle a HaxePress website theme through the HaxePress MCP theme tools, then check it in the live preview on desktop, tablet and mobile. Use this whenever someone asks to create a theme, redesign or restyle their site, change its colors, fonts or layout, build a homepage, landing page, blog or portfolio look, fix how the site looks on phones, or work in the HaxePress theme builder, even if they never say the word "theme".
metadata:
  version: '1.2.0'
---

# Designing HaxePress themes

A HaxePress visual theme is one JSON document: global tokens, a shared header and
footer, one section list per page template, and optional reusable components,
style classes, content feeds and scoped CSS. You change it only through the MCP
tools, which validate every save on the server. Everything you save is a **draft**.
People review it in the theme editor and publish it themselves; you cannot
publish or activate a theme, so never tell anyone their site has changed.

Talk to the person in their language. Keep design vocabulary plain ("the top of
the homepage", not "Home scope, section 2").

## Tool names

The same tools have two sets of names. A site-wide admin connection uses the
left column and needs a `themeId` argument; a connection made for one theme uses
the right column and needs none. Use whichever set you have.

| Admin connection                                 | Theme connection                   | Purpose                                        |
| ------------------------------------------------ | ---------------------------------- | ---------------------------------------------- |
| `list_themes`, `create_theme_draft`              | —                                  | Find or create a builder theme                 |
| `get_theme_design_guide`                         | `get_design_guide`                 | Machine-readable limits, block types, presets  |
| `get_theme_design`                               | `get_design`                       | The saved draft, its `version` and collections |
| `inspect_theme_tree`, `get_theme_section`        | —                                  | Section and block IDs; one section in full     |
| `edit_theme_design`                              | `edit_design`                      | Up to 100 atomic operations in one save        |
| `replace_theme_design`                           | `replace_design`                   | Save a complete new document                   |
| `preview_theme_design`                           | `preview_theme`                    | Screenshot of any page, on any device          |
| `search_media_for_theme`, `read_media_for_theme` | `search_media`, `read_media_image` | Site media library                             |
| `search_theme_assets`, `read_theme_asset_image`  | same                               | Images owned by the theme                      |
| `upload_theme_image`, `verify_theme_image`       | same                               | Add a new image to the theme                   |
| `set_theme_block_image`                          | —                                  | Point one block at a managed image             |
| `get_theme_collection_schema`                    | `get_collection_schema`            | Custom fields of a collection                  |

## Workflow

### 1. Understand the site before drawing anything

Find out what the site is for, who reads it and what a visitor should do first.
If the person gave only a vague brief ("make it modern"), infer the subject from
the site itself instead of asking a list of questions:

- `get_theme_design` returns the available `collections`. Read a few real
  items through the preview (step 6) so you design around real titles, image
  shapes and text lengths, not placeholder copy.
- Preview the current homepage on desktop and mobile. Note what already works;
  a redesign that loses the site's identity is rarely what people want.

Ask a question only when the answer changes the design and cannot be inferred,
such as which existing theme to modify.

### 2. Pick the theme to work on

- Editing an existing builder theme: `list_themes` shows IDs (`theme-…`); an ID
  is not derived from the theme's name, so copy it exactly.
- A new design: `create_theme_draft` with a name and `starter: "content"` (a
  working blog-style layout) or `"blank"`. The result's `redirect` is
  `/admin/themes/<id>/design`; that `<id>` is the new theme. A new theme is
  inactive, so visitors never see your work in progress.
- Packaged ZIP themes are not builder themes and cannot be edited here.

### 3. Read the contract and the current draft

Call `get_theme_design_guide` once, then `get_theme_design`. Keep the returned
`version`: every save needs it as `expectedVersion`, and every successful save
returns the next one. If a save fails because the version changed, someone else
edited the theme. Read it again and reapply your change to the new document
instead of overwriting theirs.

For targeted edits, `inspect_theme_tree` gives every section and block ID per
scope (`header`, `footer`, the template names, and `@<component>` scopes).

### 4. Decide a design direction, then write it down

Before building, settle these in a few lines (and share them with the person):

- **Palette:** background, text and one accent as hex colors. Body text needs
  a contrast ratio of at least 4.5:1 against its background; large headings and
  buttons at least 3:1.
- **Type:** `tokens.font` is a font stack. The site always loads
  `'DM Sans', Arial, sans-serif` and `'DM Serif Display', Georgia, serif`
  (`sans` and `serif` are short for these); system stacks
  (`system-ui, sans-serif`, `Georgia, serif`, `ui-monospace, monospace`) also
  work. Remote fonts and `@import` are rejected, and fonts such as Avenir or
  Helvetica Neue exist only on some visitors' devices, so don't plan around a
  typeface the site cannot load. Pages preload the bundled font that
  `tokens.font` names first, so text is drawn in it from the first paint; the
  other bundled font, used only in element styles, loads after the page.
- **Layout idea:** one sentence per template on what the reader sees first.
- **One memorable element:** a striking hero, an unusual grid, a typographic
  treatment. Keep everything around it quiet.

Ground the choices in the subject. A bakery, a law firm and a photographer
should not get the same layout with different colors. Avoid the look of a
generic template: identical rounded cards everywhere, an all-caps label above
every heading, gradient washes as decoration, centered everything, three
"feature" boxes with icons by default.

### 5. Build

- **A complete new look:** start from the document `get_theme_design`
  returned, change it in full and save with `replace_theme_design`. Keep every
  core template (`Home`, `ContentIndex`, `ContentDetail`, `Page`, `About`,
  `NotFound`) and the header and footer; the server refuses documents without
  them.
- **Changes to an existing design:** `edit_theme_design` with up to 100
  operations. They apply in order and save atomically; if one fails, nothing is
  saved. Insert and duplicate operations return the new IDs in `created`.

Build in this order, saving as you go so a validation error points at a small
change: tokens and classes → header and footer → Home → ContentIndex and
ContentDetail → Page, About and NotFound → responsive overrides.

Key rules (details in `references/document-model.md`):

- Show real content with bindings, not copied text: a `repeat` block over
  `page.items`, `page.related` or a named feed, with children bound to
  `item.title`, `item.url`, `item.image`, `item.excerpt`,
  `item.publishedLabel`. Detail pages use `content-title`, `content-image`
  and `content-body` blocks.
- Brand and menus come from site settings: use `brand` and `navigation`
  blocks rather than typing the site name or links. If the site name setting
  still says something generic, keep the `brand` block and tell the person to
  change the name in Settings; changing settings changes the live site.
- Style desktop first in `styles.desktop.normal`; override only what changes in
  `styles.tablet` and `styles.mobile`. Put repeated looks in `classes` and the
  palette in `tokens`, so later changes stay one edit.
- Links must be internal paths (`/about`), `https://`, `mailto:` or `tel:`.
  Forms must submit to a CMS route. Scripts, iframes and event attributes do
  not exist here.
- Text is always text. Every `text`, heading, button label, `alt` value and
  bound value is escaped when the page renders, so tags or entities you type
  appear literally. Write plain text and build structure with blocks. Only
  trusted HTML renders as HTML: the article body in `content-body`, which the
  site renders from Markdown, and the site's icons.
- Images must be managed: from the media library, from the theme's own assets
  or uploaded with `upload_theme_image` then `verify_theme_image`. Remote image
  URLs are rejected. Write real `alt` text for every meaningful image.

Operation syntax, ready sections and examples are in
`references/edit-operations.md`. Before writing `css` or styling inside
ready-made blocks, read `references/rendered-markup.md`: it lists the HTML
each block renders, the breakpoints and how the cascade orders rules, so you
never need to save trial CSS to discover selectors.

### 6. Look at it, on every device

Never report a design as finished without seeing it. Use
`preview_theme_design` (it shows the saved draft by default) and follow
`references/visual-review.md`. At minimum:

| Page                                                | Desktop              | Mobile |
| --------------------------------------------------- | -------------------- | ------ |
| `/` full page                                       | yes                  | yes    |
| A content archive (from the homepage links)         | yes                  | yes    |
| A content item (follow a link from the archive)     | yes                  | yes    |
| `/about` and a missing page such as `/no-such-page` | one device is enough |        |

Check tablet for the homepage too. Fix what you find and look again; most
designs need two or three rounds.

### 7. Hand over

Summarize in the person's language: the direction you chose and why, what
changed on each page, which pages and devices you checked, and anything left
open (missing images, a collection with no content yet). Tell them the work is
a saved draft: they can review it in **Themes → the theme's editor** and
publish it there when they are happy.

## When a save is rejected

The server's error message names the rule. The common ones and their fixes are
listed at the end of `references/document-model.md`. Read the document again
before retrying, because a failed save changes nothing.
