# Theme-owned images

The visual editor's image picker and upload controls use **Theme images**. Confirmed JPEG, PNG and GIF files belong to a specific theme and are stored through the configured `theme_assets` Storage disk at `private/storage/themes/<theme-id>/`. Metadata lives in `theme_assets`, with a foreign key to the owning design. Saved WebP images retain their existing URLs.

Images can appear in normal blocks, reusable components, responsive/interaction styles, CSS backgrounds and imported HTML/CSS. Values use immutable `/theme-assets/<theme-id>/ta_<token>.<extension>` URLs. The distinct filename namespace keeps theme-owned files outside the generic site-media dependency scanner. Native validation rejects another theme's image or a missing owned asset. Existing site-media references remain readable for older designs and dynamic content bindings.

Uploads require theme-management permission, a valid administrator session and CSRF. The editor stages the file at `POST /admin/themes/{theme-id}/assets` and uses the [same browser hash and display checks as site media](SITE-IDENTITY.md). It confirms the upload at `POST /admin/themes/{theme-id}/assets/verify`. Confirmation is scoped to the originating session and theme. The public image route streams the saved file through `Storage.response` without starting a session.

Libraries use SQL filtering, aggregate counts and bounded cursor pages. Cache keys include the theme, query, cursor and page size; image lookups are scoped to one filename. Cached records come from native model `toObject()` output. Storage budgets use the query builder's validated `sum` aggregate rather than loading asset rows; the installed framework compatibility implementation is maintained in `patches/hxwell-query-builder.patch`.

An image referenced by the current draft or published design cannot be deleted. The picker also protects the current unsaved document. Per-theme locks serialize asset removal against validation and design writes. Removing an inactive theme removes its owned directory and metadata; another theme's copy remains independent.

## Portable packages

**Export theme** includes every image owned by the theme, even unused uploads, plus referenced legacy site-media images. It does not export unrelated site-media files. The ZIP contains `cms-package.json`, `theme-design.json`, `theme-media.json` and `media/<filename>` image entries. The manifest declares the source image prefix. Exports use bounded streams and remove their temporary ZIP after completion or a disconnected download.

Import checks the signatures and dimensions of bundled JPEG, PNG and GIF images and rewrites both block and CSS references to the destination theme's prefix. Convert any WebP images in a ZIP to a supported format and update the references before importing it. Older visual-theme packages using media-library filenames are converted to the theme namespace. Same-name, different-byte updates receive a new immutable filename. Failed imports roll back metadata and compensate newly written files.

Package ZIPs allow up to 64 MB, with separate per-file, expanded-size and file-count limits. A theme's image library has a 62 MB total budget and up to 128 images, leaving space for its design/metadata within an export. Individual images retain the 5 MB / 20 megapixel validation. `MAX_CONTENT_LENGTH` controls the HTTP request ceiling; customized lower limits remain effective. The deployment updates the earlier default 12 MB ceiling to 64 MB.

## AI and browser tools

The authenticated MCP/browser APIs add:

| Tool                     | Permission  | Purpose                                                                                                                  |
| ------------------------ | ----------- | ------------------------------------------------------------------------------------------------------------------------ |
| `search_theme_assets`    | Read design | Search this theme's bounded image library.                                                                               |
| `read_theme_asset_image` | Read design | View an owned image by its library ID.                                                                                   |
| `upload_theme_image`     | Edit design | Stage canonical Base64 image data and return the image, upload ID and SHA-256.                                           |
| `verify_theme_image`     | Edit design | Confirm a displayed and hash-checked image with its ID, hash and measured dimensions. Returns the saved theme image URL. |

Site-media browsing keeps its separate media permission. Theme-owned assets are part of the design and do not require access to the general media library. Images uploaded through these tools join the same theme export. The editor and AI still use the same native design validator, ownership checks and save path.

Run `python3 tests/run.py --only theme_assets`, `--only theme_export` and `--only theme_mcp` after building the native application, UI and protocol worker. The coverage includes separate Storage/ORM counts, scope/auth/CSRF, SQL budgets, CSS/rendering, reference protection, unused images, a package above the previous 10 MB ceiling, import ownership/collision rebasing and complete uninstall.
