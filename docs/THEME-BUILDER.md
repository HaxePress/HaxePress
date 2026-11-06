# Composable theme builder

Open **Themes → Create theme**. Choose a content starter or an empty homepage. Packaged ZIP themes keep their Wellout views and customization workflows.

The editor uses a nested document tree. Sections contain elements; containers, rows, columns, grids and repeaters can contain further elements. Reorder them before or after a sibling, move them into another container, or use the inspector's move controls. Descendant moves cannot introduce cycles. Deep branches can be collapsed. Canvas clicks select the innermost editable element. A resize handle supports dragging and arrow keys; Shift increases the keyboard step.

The **Add** panel provides layout starting points and individual elements. A starter is editable structure rather than a locked widget. The HTML element supports semantic HTML and inline SVG. Headings, text, images, links, navigation, branding, content bodies, search, pagination and plugin slots can be composed together. Existing content-list widgets have a **Customize card layout** action that converts them into an editable repeater.

The **Style** inspector controls Flexbox/Grid, dimensions, spacing, typography, backgrounds, borders, positioning and effects. Desktop is the base; tablet and mobile override it. Normal, hover and focus states are independent. Clear a declaration to inherit it. **Advanced → All CSS properties** accepts additional CSS declarations and custom properties. Absolute positioning gets a mobile flow fallback; the user can override it. The preview uses actual 1280, 768 and 390 pixel iframe viewports, scaled to fit the workspace.

The **Design** panel edits global tokens, reusable style classes and a theme stylesheet. Class names also appear on their elements. The stylesheet is enclosed in native CSS `@scope (.hp-design)`, so selectors and `:scope` target the theme. Media queries, pseudo-elements and keyframes can be authored there. CSS resource URLs must point to managed media or application assets. CSS escapes in resource URLs are canonicalized before persistence so media references remain visible. See [the CSS scoping specification](https://www.w3.org/TR/css-cascade-6/#scoped-styles).

**Import HTML** parses an inert browser template and converts it into editable nodes. Inline styles and style blocks are retained. Scripts, embedded documents and executable attributes are omitted. Images must already use managed library addresses. The proposed document is normalized and validated on the server before it enters the preview; import does not save or publish it.

Header and footer are shared across public templates. Core templates remain available; the template picker can create additional named templates with a CMS context. Publishing registers their names, labels and scopes in the theme manifest. Assign them through CMS homepage/content-type settings. A published template still assigned to CMS settings cannot be removed. Component definitions can be saved from a selection, instantiated in layouts or repeaters, and edited through the same picker. Changes apply to every instance. Definitions cannot contain themselves, directly or indirectly; remove instances before deleting a definition.

Repeaters use current-page content, related content, or a named collection source. Design the complete item markup with child elements and bind values such as `item.title`, `item.url`, `item.image`, `item.fields.price`, `site.site_name` or `collection.name`. Conditional visibility supports present, empty and equality tests. The binding context excludes authentication and private settings. Custom fields follow the CMS's existing public/list visibility rules; list sources never project content bodies.

The **Sources** panel defines a collection, category, tag, search, SQL sort and a maximum of 24 records. Only sources referenced by the visible template, header/footer and used components are resolved. Each query has a filter/limit/sort-specific cache key and selects summary columns. Editing a source uses a CSRF-protected transient preview endpoint without saving the draft. Existing public controllers prepare archive/detail preview data; pagination remains native to the archive query.

**Save draft** persists work without publishing it. **Publish** saves and publishes the current document. An inactive theme still needs activation. Publishing an active theme updates it immediately. Concurrent editors use optimistic versions; stale saves are rejected. Navigation warns about unsaved changes. Undo/redo retain 40 local states.

Both drafts and published documents hold independent media dependencies, including nested images and CSS backgrounds. An image remains protected while any design, content or plugin references it. Removing it from a draft does not release its published reference. Uninstalling an inactive visual theme removes the document and its design references while preserving other owners' dependencies.

Documents use schema 2 in `theme_designs`, separate from package metadata. Schema 1 is upgraded for editing/rendering without rewriting stored documents on reads. Saving explicitly writes the canonical schema 2 form. The validator bounds documents to 1 MB, 2048 nodes, 16 nested tree levels and 20000 expanded elements per template. Templates/components/classes and collection sources have bounded catalogues. Media dependency values support up to 2 MB; each reference retains the existing 128-asset bound. These budgets bound server work rather than prescribing a page layout.

Verification: `tests/theme_builder_model.mjs`, `tests/theme_builder.py` and `tests/composable_themes.py` cover nested moves, cycles, legacy reads, classes, responsive/hover CSS, components, custom template assignment, query limits, body projection guards, warm query caches, CSS resource validation, media retention, CSRF and permissions. Run them through `npm run test:theme-builder` and `tests/run.py --only composable_themes`.

## Beginner workflow

The editor opens in **Easy** mode. The three-step creation screen chooses a business, portfolio, news or empty-page starter, then a design name, palette and type style. The server validates the complete starter document before creating an unpublished draft. The public site stays unchanged.

Easy mode exposes **Pages**, **Add**, **Look and feel** and **Content**. It edits the complete document without requiring a mode switch. The nested page outline includes groups, custom elements, plugin areas and hidden items. Drag to reorder or nest them; the inspector also offers move-up/down buttons and a destination picker for moves between pages, sections and saved parts. Canvas resize handles work with the pointer or keyboard in both modes.

The Add panel includes ready sections, every individual element, layout starting points, saved parts and HTML import. New elements go inside the selected group or beside the selected item. Page layout creation supplies an identifier automatically, with a manual override available. Saved parts can be renamed, reused and edited from the page picker; definitions in use cannot be deleted.

Click an element for text, picture, size or spacing controls; double-click plain text in the iframe for native plaintext editing. Escape cancels an inline edit, and Enter commits a heading/button edit. Dynamic content points to its CMS editor. Media selection and upload use the existing managed library, including background images and shared style backgrounds.

Appearance edits target the selected preview size and normal, hover or focus state. Desktop is the base, tablet overrides desktop, and mobile overrides both. Quick arrangement controls include stack/row/grid, dimensions and units, spacing, free placement, sticky positioning, visibility, backgrounds and shadows. Detailed groups retain the full content, CSS, attributes, class, binding and conditional-visibility controls. Clearing or resetting an override restores inheritance. Desktop heading presets preserve explicitly authored smaller-screen sizes.

Look and feel includes every global design token, shared styles and custom CSS. Content configures the same bounded collection sources used by Advanced mode, and both modes can choose and refresh the CMS preview collection. Page layouts still need assignment to a CMS page or content type; creating a layout does not create a public URL.

Draft changes save after a short idle period. Saves are serialized, retain optimistic versions and keep later edits dirty until their own save completes. Errors pause automatic saves and expose retry; conflicts never overwrite another editor's changes. Undo/redo remain available. **Publish website** saves the latest document, publishes it and activates it. **Publish changes** updates an already active design. If activation fails after publication, the response still returns the committed version so retry can continue without a stale overwrite.

**Advanced** presents the same capabilities in a denser workspace. Both modes share the property panels, library, scope controls, movement logic, validation and persistence. Switching modes does not flatten or replace existing layouts.

`tests/easy_builder.py` validates all generated starters and ready sections through the native handler, draft isolation, one-step publication, persistence, optimistic conflicts and CSRF. `tests/easy_builder_fixtures.mjs` executes the actual TypeScript factories used by the wizard.

## Portable visual theme packages

**Export theme** in the editor downloads the current document, including unsaved edits, without saving, publishing or activating it. On the Themes page, the same action downloads the latest saved draft. Both exports require theme-management permission; editor POST exports use the native CSRF and validation middleware.

The ZIP contains `cms-package.json`, `theme-design.json`, `theme-media.json` and only the managed images referenced by the design. The manifest declares the visual `builder` layout, the exact CMS/API release and the source media prefix. Custom templates, nested blocks, responsive states, components, classes, feeds and scoped CSS remain editable. Media titles and alternative descriptions are retained. Content records, accounts, site settings and connection keys are outside the archive.

Upload the ZIP through **Themes → Upload theme**. The normal package inspection validates the bounded design, media manifest and each image. A new design is installed as an inactive, published snapshot that can be previewed, activated and edited. Replacing an existing visual theme is explicit, keeps its active status and advances its optimistic version. Referenced CMS templates cannot be removed by replacement. Visual and packaged themes cannot replace one another.

Import rebases managed URLs to the destination disk. Identical existing files are reused; a conflicting filename gets a new managed name, and nested image/CSS references follow it. Images and design/package records commit together; failed transactions remove only newly created files. Draft and published media dependencies protect imported assets from library deletion.

Exports use native Haxe ZIP headers and central-directory records, retaining one bounded entry payload at a time. ZIPs stay within the existing 10 MB compressed, 32 MB expanded, 16 MB per-entry and 256-entry limits; images retain the native 5 MB and dimension bounds. File reads/writes and downloads use configured Storage disks. Temporary ZIP cleanup runs when the native download stream closes, including disconnects before and during delivery.

`tests/theme_export.py` verifies saved/unsaved exports, ZIP contents, media and metadata, collision handling, schema compatibility, replacement versions, authorization, CSRF and disconnect cleanup.

AI design connections are documented in [Theme designer MCP](THEME-MCP.md).
