# Site identity

Settings → Site details manages the site name, logo, optional publisher name, short description and optional site introduction. These fields describe a website, team or organization without requiring a personal author profile. Administrator account names are managed separately.

Upload a logo directly or choose an existing Media Library image, then save the settings. Removing a logo clears its assignment and restores the site name in the theme's own wordmark font. It does not delete the uploaded asset. Simple, Fieldnotes, Notebook and Gallery support both image and text branding, including theme previews. Image logos use the site name as their accessible text and retain their aspect ratio.

The upload pipeline accepts PNG, JPEG and GIF files up to 5 MB. The browser compares the SHA-256 hashes of the selected file and the bytes returned by the server. It opens the returned image and checks that it fits within 20 megapixels and 10,000 pixels per dimension. On success it confirms the upload automatically. Browser hashing uses Web Crypto, which requires HTTPS or a local development origin.

`POST /admin/media/upload` returns the staged image with status 202 and an `X-Upload-Id` header. The browser sends that ID, `sha256`, `width` and `height` as JSON to `POST /admin/media/upload/verify`. The server checks the session, image signature, byte count, hash and dimension limits, then saves the original bytes without decoding or re-encoding the image. Unconfirmed uploads expire after ten minutes and are removed by scheduled cleanup. Saved WebP files can still be served and selected as logos.

Public `site` props expose `site_name`, `site_logo`, `publisher_name`, `description` and `about_site`. `site_logo` is either an empty string or the canonical URL of a registered, available Media Library asset. External URLs and missing files are rejected. Logo assignment uses the same media lock as deletion; the persisted setting protects the asset through the [media dependency checks](MEDIA-DEPENDENCIES.md).

The upgrade moves existing `author_name` values to `publisher_name` and `author_bio` values to `about_site`. Existing canonical values take precedence. Legacy keys are then removed, and rerunning the migration preserves the result. The user's existing content, administrator profile, settings values and files remain intact.

The HTTP suite verifies transparent PNG uploads, private staging and expiry, serving saved WebP logos, unmodified served bytes, all four theme previews, cache invalidation, empty-logo fallback, rejection of unmanaged URLs and protection while a logo is assigned. Startup tests verify legacy-value preservation and idempotency.
