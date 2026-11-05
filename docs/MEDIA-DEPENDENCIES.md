# Media deletion and plugin dependencies

Media deletion checks live database predicates before changing the file or catalog. Stored content in every status, cover/body/text fields, custom field values, revisions, working copies, site/package settings (including encrypted package fields), menu URLs, plugin JSON values and declared model relationships protect the asset. Filename matching also covers absolute URLs, query strings, fragments and JSON-escaped slashes.

Incoming foreign keys to `media_assets` are inspected through Schema metadata and checked with the native query builder. A dependent row blocks library deletion even when its database action is `CASCADE`. Composite keys and references to a unique filename are supported. SQL statement construction remains inside the framework compatibility patch. Metadata follows [SQLite foreign-key introspection](https://www.sqlite.org/pragma.html#pragma_foreign_key_list) and [MySQL key-column metadata](https://dev.mysql.com/doc/refman/8.4/en/information-schema-key-column-usage-table.html); native integration verification uses SQLite.

No dependency result is cached to authorize deletion. Missing dependency connections/columns or failed queries block deletion. A removed table contains no data and does not block by itself. Failed/blocked deletion leaves both the original catalog record and file unchanged. The catalog deletion connection enables native foreign-key enforcement as an additional integrity check.

## Library controls and reference details

The Media Library prepares live `can_delete` and `references_verified` flags for its bounded page of images. Referenced images have a disabled delete control and a **References** button. Unverifiable dependencies keep deletion locked. These presentation flags are calculated after retrieving cached image records; the deletion service still rechecks current dependencies under the media lock.

`GET /admin/media/{id}/references` requires the `media` capability and returns up to 20 usage locations, a cursor URL in `next`, `canDelete` and `verified`. The dialog follows that cursor through content, custom fields, revisions, working copies, settings, package/plugin values, retained references, watched models and native database relationships. SQL predicates filter each source; model projections omit content bodies and stored values. Candidate metadata for encrypted settings and watched sources is traversed in batches of 32. Schema metadata describes incoming foreign keys; dependent rows remain behind specific `exists` predicates.

Accessible content links to its editor. Site, collection, taxonomy and navigation references link to their management screens. Plugin-owned references display the package and registered label/reference key; uninstalled owners remain visible without inventing a record URL. Watched models and arbitrary foreign keys identify the stored dependency location, since their custom record routes cannot be inferred.

The report respects collection, author and configuration capabilities. Restricted locations have a generic label and no link; working copies from another account remain private. No raw custom-field value, working-copy payload, revision snapshot or decrypted package setting is returned. Reference responses are private and not cacheable. Refresh updates the selected image's delete state, and unavailable sources are shown as an incomplete report.

## Persistent plugin references

Native plugins can retain media by ID. Scope is derived from the package slug; another owner cannot release the reference through this API.

```haxe
import hx.press.media.MediaDependencies;

var media = MediaDependencies.forPlugin("gallery");
media.retain(imageId, "gallery:42", "Gallery cover");
media.replace("gallery:42", selectedImageIds, "Gallery images");
```

For writes, reserve the assets before persisting the data:

```haxe
media.withReferences("gallery:42", selectedImageIds, () -> {
    Gallery.query.where("id", 42).update(["cover_id" => selectedImageIds[0]]);
    return true;
});
```

The callback runs under the shared media lock. Normal model writes remain native; use an explicit database transaction inside the callback when multiple application writes need atomicity. If the writer fails, old and newly reserved references stay protected. A later successful replacement removes obsolete references. `withValue(reference, value, callback)` discovers managed filenames in bounded nested JSON/text/encoded values and reserves their IDs. There are at most 128 assets per operation.

`PluginDatabase.put` uses this reference path automatically for managed media values. `forget` removes its value-specific reservation after deleting the stored value. Existing default-connection plugin JSON is also checked directly; configured alternate connections are registered as persistent model sources.

After deleting the actual owning data, release its references:

```haxe
Gallery.query.where("id", 42).delete();
media.forget("gallery:42");
```

Do not release stored-data references in `onDestroy`. Deactivation, failed startup and uninstall do not remove dependency records or source declarations; plugin-owned data survives those operations. Reinstalling the same package slug reuses its namespace.

## Existing models and alternate storage

Declare soft model links that have no database foreign key:

```haxe
import hx.press.media.MediaDependencyMode;

media.watch("gallery-covers", new Gallery(), "cover_id", MediaDependencyMode.Id);
media.watch("gallery-description", new Gallery(), "description", MediaDependencyMode.Text);
```

Modes are `Id`, `Url`, `Filename` and `Text`. URL/text checks handle managed filenames inside relative/absolute addresses, Markdown or JSON. The model supplies its table, connection and declared column metadata. Deletion issues specific `exists` predicates, and source definitions are traversed in batches of 32. No plugin class needs to be loaded to check a stored declaration after uninstall. Re-register the same source name after a deliberate schema migration to update its column/connection.

References in arbitrary binary files, external services or runtime-only plugin state must use `retain`/`withReferences`; their meaning cannot be inferred from an undeclared numeric or opaque value. Such plugins must establish and keep the reference for as long as their data depends on the file. Theme code can use the identical owner-scoped contract through `MediaDependencies.forTheme(slug)`.

## Verification

The HTTP suite installs an actual JVM plugin and checks normal/disabled/uninstalled/reinstalled owners, watched model IDs, nested JSON, encrypted settings, live source changes, missing connections/columns and byte-for-byte preservation after blocked deletion. Shared native checks cover owner isolation, explicit references, encoded values, model/URL sources, automatic CASCADE discovery, failed writers and deletion guards on JVM, CPPIA and PHP. Direct foreign-key constraint rejection is also verified on JVM/PHP; hxcpp's bundled SQLite repeats a failed constraint while finalizing its next statement, so its shared suite verifies the guard before attempting a database write.
