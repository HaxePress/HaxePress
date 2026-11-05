# Site identity

Settings → Site details manages the site name, logo, optional publisher name, short description and optional site introduction. These fields describe a website, team or organization without requiring a personal author profile. Administrator account names are managed separately.

Upload a logo directly or choose an existing Media Library image, then save the settings. Removing a logo clears its assignment and restores the site name in the theme's own wordmark font. It does not delete the uploaded asset. Simple, Fieldnotes, Notebook and Gallery support both image and text branding, including theme previews. Image logos use the site name as their accessible text and retain their aspect ratio.

PNG, WebP, JPEG and GIF use the shared managed-image upload pipeline: 5 MB, 20 megapixels and 10,000 pixels per dimension. The server detects the actual format, reads its dimensions and decodes it before accepting it. Original bytes are retained, preserving transparency. WebP decoding uses the standard JVM ImageIO service registry with the pinned [TwelveMonkeys WebP plugin](https://github.com/haraldk/TwelveMonkeys/tree/twelvemonkeys-3.15.3/imageio/imageio-webp). Its runtime dependencies are recorded in `dependencies.lock.json` and installed by `scripts/setup.py`.

Public `site` props expose `site_name`, `site_logo`, `publisher_name`, `description` and `about_site`. `site_logo` is either an empty string or the canonical URL of a registered, available Media Library asset. External URLs and missing files are rejected. Logo assignment uses the same media lock as deletion; the persisted setting protects the asset through the [media dependency checks](MEDIA-DEPENDENCIES.md).

The upgrade moves existing `author_name` values to `publisher_name` and `author_bio` values to `about_site`. Existing canonical values take precedence. Legacy keys are then removed, and rerunning the migration preserves the result. The user's existing content, administrator profile, settings values and files remain intact.

The HTTP suite verifies transparent PNG, lossy/lossless WebP, genuine decoding, unmodified served bytes, all four theme previews, cache invalidation, empty-logo fallback, rejection of unmanaged URLs and protection while a logo is assigned. Startup tests verify legacy-value preservation and idempotency. Browser checks exercise upload, Media Library selection, saving/removal and desktop/mobile rendering.
