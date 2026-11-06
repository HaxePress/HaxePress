package hx.press;

import hx.press.media.MediaReferences;
import hx.press.ContentCache;
import hx.press.MediaStorage;
import hx.press.MediaStorage.StoredImage;
import hx.press.Pagination;
import hx.press.Pagination.PageCursor;
import hx.press.SiteSettingsStore;
import hx.press.data.QueryPage;
import haxe.Exception;
import hx.well.database.query.QueryBuilder;
import hx.well.facades.DBStatic;
import hx.well.facades.Storage;
import hx.press.model.MediaAsset;
import hx.press.model.ContentItem;
import hx.press.model.Setting;
import hx.press.media.MediaLocks;
import hx.press.media.MediaUsage;
import hx.well.facades.Schema;

typedef MediaRecord = {
    var id:Int;
    var filename:String;
    var title:String;
    var alt:String;
    var mime_type:String;
    var width:Int;
    var height:Int;
    var size:Int;
}

class MediaCatalog {
    public static inline var PAGE_SIZE = 24;
    static final columns = ["id", "filename", "title", "alt", "mime_type", "width", "height", "size"];

    public static function register(image:StoredImage, label:String = "", alt:String = ""):Int {
        var existing = MediaAsset.query.select(["id"])
            .where("filename", image.filename)
            .limit(1)
            .first();
        if (existing != null) {
            return existing.id;
        }
        var id = MediaAsset.query.insert([
            "filename" => image.filename,
            "title" => label == "" ? image.filename : label.substr(0, 180),
            "alt" => alt.substr(0, 500),
            "mime_type" => image.contentType,
            "width" => image.width,
            "height" => image.height,
            "size" => image.size,
            "created_at" => SiteSettingsStore.timestamp(),
            "updated_at" => SiteSettingsStore.timestamp()
        ]);
        ContentCache.changed("media");
        return id;
    }

    public static function importExisting():Void {
        if (Setting.query.where("key", "cms_media_v1").exists()) {
            return;
        }
        Storage.disk("media").makeDirectory("");
        var disk = Storage.disk("media");
        for (filename in disk.files()) {
            if (!MediaReferences.validFilename(filename)
                || MediaAsset.query.where("filename", filename).exists()) {
                continue;
            }
            var size = disk.size(filename);
            if (size > MediaReferences.MAX_BYTES) {
                continue;
            }
            var bytes = disk.getBytes(filename);
            var dimensions = MediaStorage.dimensions(bytes);
            if (dimensions == null) {
                continue;
            }
            var source = ContentItem.query.select(["title", "image_alt"])
                .where("image", disk.url(filename))
                .orderBy("id")
                .limit(1)
                .first();
            var label = source == null ? filename : source.title;
            var alt = source == null ? "" : source.image_alt;
            register({
                id: 0,
                filename: filename,
                url: disk.url(filename),
                contentType: disk.mimeType(filename),
                width: dimensions.width,
                height: dimensions.height,
                size: size
            }, label, alt);
        }
        Setting.query.insert(["key" => "cms_media_v1", "value" => "1"]);
    }

    static function filter(query:QueryBuilder<MediaAsset>, search:String):Void {
        if (search != "") {
            var escaped = StringTools.replace(StringTools.replace(StringTools.replace(search, "!",
                "!!"), "%", "!%"), "_", "!_");
            var pattern = '%${escaped}%';
            query.where(matches -> {
                matches.whereLike("title", pattern)
                    .orWhereLike("alt", pattern)
                    .orWhereLike("filename", pattern);
            });
        }
    }

    public static function page(search:String, cursor:Null<PageCursor>):QueryPage<MediaRecord> {
        return ContentCache.remember("media", "library",
            [search, Pagination.token(cursor), PAGE_SIZE], () -> {
                var query = MediaAsset.query.select(columns);
                filter(query, search);
                if (cursor != null) {
                    query.where("id", cursor.before ? ">" : "<", cursor.id);
                }
                var direction = cursor != null && cursor.before ? "ASC" : "DESC";
                var rows:Array<MediaRecord> = query.orderBy("id", direction)
                    .limit(PAGE_SIZE + 1)
                    .get()
                    .map(model -> cast model.toObject());
                return Pagination.slice(rows, PAGE_SIZE, cursor);
            });
    }

    public static function count(search:String):Int {
        return ContentCache.remember("media", "count", [search], () -> {
            var query = MediaAsset.query.select(["id"]);
            filter(query, search);
            return query.count();
        });
    }

    public static function used(filename:String):Bool {
        var asset = MediaAsset.query.select(["id"]).where("filename", filename).limit(1).first();
        return asset != null && MediaUsage.used(asset.id, filename);
    }

    public static function remove(id:Int):Void {
        MediaLocks.run(() -> {
            Schema.enableForeignKeyConstraints();
            var image = MediaAsset.query.select(["id", "filename", "title"])
                .where("id", id)
                .limit(1)
                .first();
            if (image == null) {
                return false;
            }
            if (MediaUsage.used(image.id, image.filename)) {
                throw new Exception("This image is referenced by content, settings or a plugin. Remove those references first.");
            }
            var disk = Storage.disk("media");
            var path = image.filename;
            var quarantine = '.${image.filename}.deleting';
            var moved = disk.fileExists(path);
            if (moved) {
                disk.move(path, quarantine);
            }
            try {
                DBStatic.transaction(() -> {
                    image.delete();
                    Activity.record("deleted", "media", image.id, image.title);
                });
            } catch (error:Dynamic) {
                if (moved) {
                    disk.move(quarantine, path);
                }
                throw error;
            }
            if (moved) {
                disk.delete(quarantine);
            }
            ContentCache.changed("media");
            return true;
        });
    }
}
