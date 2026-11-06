# The markup a design renders

Read this before writing `css` or styling inside ready-made blocks such as
`content-list`. The preview returns screenshots, not HTML, and `read_admin`
returns page data rather than markup, so this page is the only map of the
rendered page. Use it instead of saving trial CSS to find selectors.

## Page structure

```html
<div class="hp-design">
  <!-- the @scope root of `css` -->
  <section data-design-node="SECTION_ID" class="hp-design-section CLASSES">
    <div class="hp-design-section-inner width-content">
      <!-- grid of `columns` -->
      BLOCKS
    </div>
  </section>
</div>
```

The header, each template and the footer are sequences of these sections.

## Blocks

Every block carries `data-design-node="ID"`, `data-block-id="ID"` and
`class="hp-design-node NAME design-class-NAME …"` for each name in its
`classes`, plus a type class below.

| Type                | Renders as                                                                                                                                                                                                                                       |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `container`         | `<div>` with its children                                                                                                                                                                                                                        |
| `element`           | the chosen `tag`, with its `attributes` and children                                                                                                                                                                                             |
| `heading`           | `<h1>`–`<h6>`; with an `href`, the text is wrapped in `<a>`                                                                                                                                                                                      |
| `text`              | `<p class="hp-design-text">` (white space is kept)                                                                                                                                                                                               |
| `image`             | `<figure class="hp-design-image-node"><img class="hp-design-image"></figure>`, or `<a class="hp-design-image-link">…</a>` when it has an `href`                                                                                                  |
| `button`            | `<a class="hp-design-button">`                                                                                                                                                                                                                   |
| `brand`             | `<a class="hp-design-brand" href="/">` with the logo image or the site name                                                                                                                                                                      |
| `navigation`        | `<nav>` with one `<a>` per menu link; the current page's link has `class="active"`                                                                                                                                                               |
| `repeat`            | `<div class="hp-design-repeater">` with the children repeated per item, as siblings                                                                                                                                                              |
| `component`         | `<div class="hp-design-component">` with the component's sections                                                                                                                                                                                |
| `content-title`     | `<h1>`                                                                                                                                                                                                                                           |
| `content-excerpt`   | `<p class="hp-design-excerpt">`                                                                                                                                                                                                                  |
| `content-image`     | `<figure class="hp-design-image-node"><img class="hp-design-image"></figure>`                                                                                                                                                                    |
| `content-body`      | `<div class="hp-design-prose">`: a plugin area `<div class="extension-slot extension-slot-content-before">` (usually empty), the rendered Markdown, the custom fields, then a `content-after` plugin area                                        |
| `content-list`      | `<div>` with, on archives, the filter form first; then `<div class="hp-design-content-grid">` of `<article>` cards: `<a><img></a>`, `<h2><a>title</a></h2>`, `<p>` excerpt, `<time>`; on the homepage an `<a class="hp-design-archive">` follows |
| `search`            | `<div>` with the filter form                                                                                                                                                                                                                     |
| `pagination`        | `<div>` with the page links                                                                                                                                                                                                                      |
| `site-description`  | `<p>`                                                                                                                                                                                                                                            |
| `spacer`, `divider` | `<div class="hp-design-spacer">`, `<hr>`                                                                                                                                                                                                         |

Consequences worth knowing:

- **`attributes` render only on `element` blocks.** On any other type they pass
  validation and disappear. To give a box `data-*` or `aria-*` attributes,
  make it an `element` with `tag: "div"`; to style it, give it a class instead.
- **Image styles land on the wrapper** (`figure` or `a`); the `img` inside
  fills it (`width` and `height` 100%, `object-fit: cover`). Set
  `aspect-ratio` or `height` on the image block to crop it.
- **Element links:** an `element` with `tag: "a"` takes its link from the
  block's `href` field, not from an `href` attribute.
- **Article text starts after a plugin area,** so `:first-child` never matches
  the first heading or paragraph of `content-body`. Use
  `:scope .hp-design-prose > .extension-slot + *` or `:first-of-type` instead.

## Breakpoints and the cascade

- `styles.tablet` applies at `max-width: 900px` and `styles.mobile` at
  `max-width: 600px`. The preview's tablet (834px) and mobile (390px) devices
  fall inside them. Section `columns` collapse on their own at 800px and 580px.
- The stylesheet is written selector by selector: for each class, then each
  section and block, its desktop rule followed by its tablet and mobile
  rules. Classes come first, so a block's own styles win over its classes,
  even a block's desktop rule over a class's mobile rule. The order between
  two classes is not guaranteed, so one class's desktop rule can beat
  another's mobile rule. Keep a property's desktop and mobile values in the
  same place (one class, or the block itself), or write the responsive part in
  `css` inside a media query.
- Block and class rules look like `.hp-design [data-design-node="ID"]` and
  `.hp-design .design-class-NAME`. Inside `css` (wrapped in
  `@scope (.hp-design)`) a selector needs at least the same weight to beat
  them, for example `:scope .card h2` or `:scope [data-design-node="ID"]`.
  Prefer changing the block's `styles` when you only need to restyle one
  block.

## Useful selectors

```css
@media (max-width: 600px) {
  :scope .hp-design-content-grid {
    grid-template-columns: minmax(0, 1fr);
  }
}
:scope .hp-design-content-grid article h2 a {
  text-decoration: none;
}
:scope .hp-design-prose h2 {
  font-family: 'DM Serif Display', Georgia, serif;
}
:scope nav a.active {
  text-decoration: underline;
  text-underline-offset: 6px;
}
:scope .hp-design-button:hover {
  filter: none;
  background: #1f2421;
}
```
