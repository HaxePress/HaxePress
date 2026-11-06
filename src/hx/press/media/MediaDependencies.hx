package hx.press.media;

import haxe.Exception;
import haxe.Json;
import haxe.crypto.Md5;
import haxe.io.Bytes;
import hx.press.model.MediaAsset;
import hx.press.model.MediaDependency;
import hx.press.model.MediaDependencySource;
import hx.well.database.Connection;
import hx.well.model.BaseModel;
import hx.well.facades.Storage;

/** Persistent, owner-scoped references; stopping a plugin never releases its stored data. */
class MediaDependencies {
    public static inline var MAX_MEDIA_PER_REFERENCE = 128;

    public final owner:String;

    private function new(owner:String) {
        this.owner = owner;
    }

    static function namespace(kind:String, slug:String):MediaDependencies {
        if (slug == null || slug.length > 64 || !~/^[a-z0-9]+(-[a-z0-9]+)*$/.match(slug)) {
            throw new Exception("Use a valid package slug for media dependencies.");
        }
        return new MediaDependencies('${kind}-${slug}');
    }

    public static function forPlugin(slug:String):MediaDependencies {
        return namespace("plugin", slug);
    }

    public static function forTheme(slug:String):MediaDependencies {
        return namespace("theme", slug);
    }

    static function validateReference(reference:String, label:String):Void {
        if (reference == null
            || reference == ""
            || Bytes.ofString(reference).length > 200
            || ~/[\x00-\x1f\x7f]/.match(reference)
            || label == null
            || label.length > 240) {
            throw new Exception("Use a bounded, stable reference key and label for media dependencies.");
        }
    }

    static function identifiers(ids:Array<Int>):Array<Int> {
        if (ids == null || ids.length > MAX_MEDIA_PER_REFERENCE) {
            throw new Exception("A media reference can contain up to 128 assets.");
        }
        var result:Array<Int> = [];
        for (id in ids) {
            if (id < 1) {
                throw new Exception("Choose a valid media identifier.");
            }
            if (!result.contains(id)) {
                result.push(id);
            }
        }
        return result;
    }

    static function available(ids:Array<Int>):Void {
        if (ids.length == 0) {
            return;
        }
        var records:Array<{id:Int, filename:String}> = MediaAsset.query.select(["id", "filename"])
            .whereIn("id", cast ids)
            .limit(ids.length)
            .get()
            .map(model -> cast model.toObject());
        if (records.length != ids.length) {
            throw new Exception("An image is no longer available. Choose an existing library asset.");
        }
        var disk = Storage.disk("media");
        for (record in records) {
            if (!disk.fileExists(record.filename)) {
                throw new Exception("An image is no longer available. Choose an existing library asset.");
            }
        }
    }

    function retainRows(reference:String, ids:Array<Int>, label:String):Void {
        for (id in ids) {
            MediaDependency.query.upsert([
                "media_id" => id,
                "owner" => owner,
                "reference_key" => reference,
                "label" => label
            ], ["media_id", "owner", "reference_key"], ["label"]);
        }
    }

    /** Reserve before writing data. On failure both old and newly reserved assets stay protected. */
    public function withReferences<T>(reference:String, ids:Array<Int>, write:Void->T,
            label:String = ""):T {
        validateReference(reference, label);
        var selected = identifiers(ids);
        return MediaLocks.run(() -> {
            available(selected);
            retainRows(reference, selected, label);
            var result = write();
            MediaDependency.query.where("owner", owner)
                .where("reference_key", reference)
                .whereNotIn("media_id", cast selected)
                .delete();
            return result;
        });
    }

    public function replace(reference:String, ids:Array<Int>, label:String = ""):Void {
        withReferences(reference, ids, () -> true, label);
    }

    public function retain(mediaId:Int, reference:String, label:String = ""):Void {
        validateReference(reference, label);
        var selected = identifiers([mediaId]);
        MediaLocks.run(() -> {
            available(selected);
            retainRows(reference, selected, label);
            return true;
        });
    }

    public function release(mediaId:Int, reference:String):Void {
        validateReference(reference, "");
        MediaLocks.run(() -> {
            MediaDependency.query.where("owner", owner)
                .where("reference_key", reference)
                .where("media_id", mediaId)
                .delete();
            return true;
        });
    }

    /** Call after deleting the owning data, not during plugin destruction or deactivation. */
    public function forget(reference:String):Void {
        validateReference(reference, "");
        MediaLocks.run(() -> {
            MediaDependency.query.where("owner", owner).where("reference_key", reference).delete();
            return true;
        });
    }

    /** Link nested JSON, Markdown, absolute/relative URLs, encoded paths and filenames. */
    public function withValue<T>(reference:String, value:Dynamic, write:Void->T,
            label:String = ""):T {
        validateReference(reference, label);
        return MediaLocks.run(() -> {
            var referencedFilenames = filenames(value);
            var rows:Array<{id:Int}> = referencedFilenames.length == 0 ? [] : MediaAsset.query.select(["id"])
                .whereIn("filename", cast referencedFilenames)
                .limit(referencedFilenames.length)
                .get()
                .map(model -> cast model.toObject());
            if (rows.length != referencedFilenames.length) {
                throw new Exception("A referenced image is no longer available in the media library.");
            }
            return withReferences(reference, [for (row in rows) row.id], write, label);
        });
    }

    public static function filenames(value:Dynamic):Array<String> {
        var serialized = Json.stringify(value);
        if (Bytes.ofString(serialized).length > 2 * 1024 * 1024) {
            throw new Exception("Use explicit media identifiers for larger dependency values.");
        }
        var decoded = serialized;
        try {
            decoded = StringTools.urlDecode(serialized);
        } catch (_:Dynamic) {}
        var filenames:Array<String> = [];
        var pattern = ~/(?:^|[^A-Za-z0-9_-])([A-Za-z0-9_-]{32}\.(?:jpg|png|webp|gif))(?=$|[^A-Za-z0-9_.-])/g;
        var offset = 0;
        while (pattern.matchSub(decoded, offset)) {
            var filename = pattern.matched(1);
            if (!filenames.contains(filename)) {
                filenames.push(filename);
            }
            if (filenames.length > MAX_MEDIA_PER_REFERENCE) {
                throw new Exception("A media reference can contain up to 128 assets.");
            }
            var match = pattern.matchedPos();
            offset = match.pos + match.len;
        }
        return filenames;
    }

    /** Declare an existing ORM column; no runtime plugin code is needed to check it later. */
    public function watch<M>(name:String, model:BaseModel<M>, column:String,
            mode:MediaDependencyMode, label:String = ""):Void {
        validateReference(name, label);
        var table = model.getTable();
        var connection = model.__connection;
        if (table == null
            || !~/^[A-Za-z_][A-Za-z0-9_]{0,63}$/.match(table)
            || column == null
            || !model.getDatabaseFields().contains(column)
            || !~/^[A-Za-z_][A-Za-z0-9_]{0,63}$/.match(column)
            || connection == null
            || connection.length > 80
            || Connection.driver(connection) == null
            || !["id", "url", "filename", "text"].contains(mode)) {
            throw new Exception("Declare a configured ORM model, media column and supported reference mode.");
        }
        MediaLocks.run(() -> {
            var key = Md5.encode(Json.stringify([owner, name]));
            MediaDependencySource.query.upsert([
                "key" => key,
                "owner" => owner,
                "connection_name" => connection,
                "table_name" => table,
                "column_name" => column,
                "mode" => (mode : String),
                "label" => label
            ], ["key"],
                ["connection_name", "table_name", "column_name", "mode", "label"]);
            return true;
        });
    }
}
