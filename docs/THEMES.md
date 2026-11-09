# Theme previews and the built-in default

Create CMS-managed themes with sections, blocks and responsive live previews from **Themes → Create theme**. See [the visual theme builder](THEME-BUILDER.md) for drafts, publishing, templates and media protection. ZIP themes provide Wellout views and keep their customization workflow.

## Optional live customization

A theme developer declares its editable options in the existing optional `fields` list in `cms-package.json`. Omit the list or use `"fields": []` for a theme without customization controls. Only declared non-secret fields appear in **Customize** on the full preview; private settings remain on the protected settings page. Text, textarea, color, number, select and boolean controls use the package's labels, help, defaults and validation rules.

Draft changes reach the isolated iframe as the changed values in its `preview_settings` query, only for the theme's declared keys and up to 2000 characters each. The server renders the frame with those values in `theme.settings`, so templates read settings the same way with and without a draft. The page replaces the frame's document in place, so the preview keeps its scroll position and does not flash. Links inside the preview keep the customization session and the draft. The database and active site's appearance change only after **Save changes**; **Discard changes** restores the saved values. Saving uses the existing admin/CSRF-protected package settings endpoint and native handler validation.

For example, a developer can add an optional button color:

```json
{
  "fields": [
    {
      "key": "button_color",
      "label": "Button background",
      "kind": "color",
      "defaultValue": "",
      "help": "Leave unset to use the accent color."
    }
  ]
}
```

An optional empty color stays empty. The bundled layouts set `--theme-button-background` only when a six-digit color is supplied; CSS falls back to the accent color otherwise. Button text color is separately editable. Existing palette choices therefore remain effective when upgrading or clearing a custom override.

Verification: `outputs/theme-customizer-full-test.log` includes the native save/validation and opt-out cases; `outputs/theme-customizer-browser-report.json` records live updates without a reload/write, navigation retention, discard/save and mobile sizing. CPPIA/PHP checks and the production data comparison are in `outputs/theme-customizer-cppia.log`, `outputs/theme-customizer-php.log` and `outputs/theme-customizer-live-verification.json`.

## Cached cards and full previews

Theme cards cache PNG images of the real rendered homepage. A single shared capture queue opens at most one temporary authenticated preview iframe at a time, at 1280 × 800. The server renders the page in that iframe; the administration page converts it to a PNG and removes the iframe as soon as the PNG is ready, releasing its document. Cards near the viewport request captures, while the rest remain deferred. Completed cards contain ordinary images.

The frame is same-origin. After its load event, which waits for the theme stylesheet and images, the capture waits for fonts and decodes the images in view, then draws the first screen of the frame's document. The page renders with no capture code of its own, so the full preview and the captured frame are the same page.

The browser Cache API retains at most 32 PNGs for 30 minutes. Keys include the theme update, locale, admin identity, front-end build version and the content/category/tag/settings/navigation/structure/extension/media cache revisions. Relevant writes therefore produce a new preview key. A warm reload reads PNGs without opening capture frames. Navigating away cancels pending work and removes the active frame; failed or timed-out captures also remove it. Disabled/full browser storage still allows current captures to display. Clicking a card opens the live full preview, whose isolated iframe and desktop/tablet/mobile controls remain available.

Simple is part of HaxePress. Its manifest and English/Turkish catalogues are compiled as Haxe resources from `resources/themes/simple/`; its CSS is bundled into the application from `resources/css/themes/simple.css`. It has no installed package directory and needs no theme ZIP or external theme stylesheet. Fresh installations work without a package download directory.

The stable `theme-simple` identity is protected by the package service. Upload inspection and installation reject replacement ZIPs, and uninstall is rejected even while another theme is active. The panel marks it as a built-in theme and omits the uninstall control. Protection is derived from the application identity rather than an uploaded manifest flag.

Fieldnotes, Notebook and Gallery are bundled themes and belong to the application the same way. Every start installs a missing one and replaces one whose shipped archive in `private/packages` differs from the archive it was installed from, keeping its settings and activation; the setting `cms_example_<id>` records that archive's SHA-256 digest. Uploads cannot replace them and they cannot be removed. Their IDs are protected only while the installed theme is HaxePress's own, so a theme that already occupied one of these IDs is left alone. Other themes keep their normal installation, activation, settings and uninstall behavior.

## Forks

**Fork** (`POST /admin/themes/{id}/fork`) copies any theme into a new, inactive theme named “{name} copy”, authored by the administrator who forked it. Updates never touch a fork, so forking is how a bundled theme is changed:

- A packaged theme is copied file for file into a new slug, `<slug>-copy-<8 hex digits>`, staged and inspected like an upload and installed with the original's settings.
- The built-in Simple theme becomes a packaged theme whose `views` hold the application templates Simple renders (`Home`, `ContentIndex`, `ContentDetail`, `Page`, `About`, `NotFound`, `SiteLayout` and `ContentCard`) with Simple's catalogues, so it renders the same pages until it is changed.
- A visual design is copied with its draft, its published version and its theme images, whose URLs move to the copy's ID; the copy opens in the editor.

**Download** (`GET /admin/themes/{id}/download`) streams a packaged theme's installed files as a ZIP that installs as the same theme. A fork downloaded, changed and uploaded again replaces the fork and keeps its compatible settings.

Startup registers or updates the built-in definition while retaining its compatible settings, activation state and installation date. Existing active themes remain selected. Repeated startup leaves unchanged built-in records and cache generations alone. The default's catalogue hook points at its embedded translations; it does not refer to a package file tree.

Themes using the shared `simple` layout may inherit its bundled styles and omit a stylesheet. Custom layouts still provide a stylesheet. Public theme information exposes `built_in`; package summaries expose this application-derived flag and their update timestamp for the management interface.

Verification covers a fresh JVM installation with no ZIPs or external theme files, inactive uninstall and valid ZIP replacement attempts, native staged-install rejection on JVM, settings and translation preservation, and restart idempotency. JVM/CPPIA/PHP fixtures exercise portable embedded registration, catalogue loading and native persistence. Browser checks cover all four real previews, repeated loads, mobile sizing, full-preview links and activation.
