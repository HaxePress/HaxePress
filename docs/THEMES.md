# Theme previews and the built-in default

Create CMS-managed themes with sections, blocks and responsive live previews from **Themes → Create theme**. See [the visual theme builder](THEME-BUILDER.md) for drafts, publishing, templates and media protection. Existing ZIP themes retain their renderer and customization workflows.

## Optional live customization

A theme developer declares its editable options in the existing optional `fields` list in `cms-package.json`. Omit the list or use `"fields": []` for a theme without customization controls. Only declared non-secret fields appear in **Customize** on the full preview; private settings remain on the protected settings page. Text, textarea, color, number, select and boolean controls use the package's labels, help, defaults and validation rules.

Draft changes update the isolated iframe immediately through same-origin, frame/session-checked messages and Inertia's native `replaceProp("theme.settings", values)`. Themes continue reading `usePage().props.theme.settings`; renderers or frontend modules decide how each setting affects the theme. Navigation inside the preview preserves the customization session and reapplies the draft. The database and active site's appearance change only after **Save changes**; **Discard changes** restores the saved values. Saving uses the existing admin/CSRF-protected package settings endpoint and native handler validation.

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

Theme cards cache PNG images of the real rendered homepage. A single shared capture queue opens at most one temporary authenticated preview iframe at a time, at 1280 × 800. Rendering and PNG conversion happen inside that iframe; it is removed as soon as its PNG is ready, releasing its document and renderer resources. Cards near the viewport request captures, while the rest remain deferred. Completed cards contain ordinary images.

The frame URL includes a `thumbnailCapture` identifier. A capture component mounted alongside the page waits for React/Inertia Head to commit, then for the theme stylesheet, page load, fonts and visible images. It captures its own document and sends its PNG to the parent with `postMessage`; the parent verifies the frame window, origin and identifier before accepting it. The full preview has no capture parameter and stays interactive.

The browser Cache API retains at most 32 PNGs for 30 minutes. Keys include the theme update, locale, admin identity, frontend asset version and the content/category/tag/settings/navigation/structure/extension/media cache revisions. Relevant writes therefore produce a new preview key. A warm reload reads PNGs without opening capture frames. Navigating away cancels pending work and removes the active frame; failed or timed-out captures also remove it. Disabled/full browser storage still allows current captures to display. Clicking a card opens the live full preview, whose isolated iframe and desktop/tablet/mobile controls remain available.

Simple is part of HaxePress. Its manifest and English/Turkish catalogues are compiled as Haxe resources from `resources/themes/simple/`; its CSS is bundled into the application from `resources/css/themes/simple.css`. It has no installed package directory and needs no theme ZIP, renderer module or external theme stylesheet. Fresh installations work without a package download directory.

The stable `theme-simple` identity is protected by the package service. Upload inspection and installation reject replacement ZIPs, and uninstall is rejected even while another theme is active. The panel marks it as a built-in theme and omits the uninstall control. Protection is derived from the application identity rather than an uploaded manifest flag. Other themes keep their normal installation, activation, settings and uninstall behavior.

Startup registers or updates the built-in definition while retaining its compatible settings, activation state and installation date. Existing active themes remain selected. Repeated startup leaves unchanged built-in records and cache generations alone. The default's catalogue hook points at its embedded translations; it does not refer to a package file tree.

Themes using the shared `simple` layout may inherit its bundled styles and omit a stylesheet. Custom layouts still provide a stylesheet. Public theme information exposes `built_in`; package summaries expose this application-derived flag and their update timestamp for the management interface.

Verification covers a fresh JVM installation with no ZIPs or external theme files, inactive uninstall and valid ZIP replacement attempts, native staged-install rejection on JVM, settings and translation preservation, and restart idempotency. JVM/CPPIA/PHP fixtures exercise portable embedded registration, catalogue loading and native persistence. Browser checks cover all four real previews, repeated loads, mobile sizing, full-preview links and activation.
