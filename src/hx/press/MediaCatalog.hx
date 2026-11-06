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
import hx.well.storage.StorageDisk;
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
    var trashed_epoch:Float;
}

class MediaCatalog {
    public static inline var PAGE_SIZE = 24;

    /** Trashed images wait in this hidden folder of the media disk, which no URL serves. **/
    public static inline var TRASH_FOLDER = ".trash";

    /** Days an image stays in the trash before it is deleted permanently. **/
    public static inline var TRASH_DAYS = 30;

    static inline var DAY_MS = 24 * 60 * 60 * 1000.0;
    static inline var PURGE_BATCH = 50;
    static final columns = [
        "id",
        "filename",
        "title",
        "alt",
        "mime_type",
        "width",
        "height",
        "size",
        "trashed_epoch"
    ];
    static final referenced = "This image is referenced by content, settings or a plugin. Remove those references first.";

    public static function trashPath(filename:String):String {
        return '${TRASH_FOLDER}/${filename}';
    }

    /** When an image in the trash is deleted permanently, in milliseconds since the epoch. **/
    public static function expires(trashedEpoch:Float):Float {
        return trashedEpoch + TRASH_DAYS * DAY_MS;
    }

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

    static function filter(query:QueryBuilder<MediaAsset>, search:String, trashed:Bool):Void {
        query.where("trashed_epoch", trashed ? ">" : "=", 0);
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

    public static function page(search:String, cursor:Null<PageCursor>,
            trashed:Bool = false):QueryPage<MediaRecord> {
        return ContentCache.remember("media", "library",
            [search, trashed, Pagination.token(cursor), PAGE_SIZE], () -> {
                var query = MediaAsset.query.select(columns);
                filter(query, search, trashed);
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

    public static function count(search:String, trashed:Bool = false):Int {
        return ContentCache.remember("media", "count", [search, trashed], () -> {
            var query = MediaAsset.query.select(["id"]);
            filter(query, search, trashed);
            return query.count();
        });
    }

    public static function used(filename:String):Bool {
        var asset = MediaAsset.query.select(["id"]).where("filename", filename).limit(1).first();
        return asset != null && MediaUsage.used(asset.id, filename);
    }

    /**
        Moves an unused image to the trash. Its file moves to the hidden trash
        folder, so its public URL stops working until it is restored.
    **/
    public static function trash(id:Int):Void {
        MediaLocks.run(() -> {
            var image = MediaAsset.query.select(["id", "filename", "title"])
                .where("id", id)
                .where("trashed_epoch", 0)
                .limit(1)
                .first();
            if (image == null) {
                return false;
            }
            if (MediaUsage.used(image.id, image.filename)) {
                throw new Exception(referenced);
            }
            var disk = Storage.disk("media");
            disk.makeDirectory(TRASH_FOLDER);
            var trashed = trashPath(image.filename);
            var moved = moveFile(disk, image.filename, trashed);
            try {
                DBStatic.transaction(() -> {
                    MediaAsset.query.where("id", image.id)
                        .update(["trashed_epoch" => Date.now().getTime()]);
                    Activity.record("trashed", "media", image.id, image.title);
                });
            } catch (error:Dynamic) {
                if (moved) {
                    disk.move(trashed, image.filename);
                }
                throw error;
            }
            ContentCache.changed("media");
            return true;
        });
    }

    public static function restore(id:Int):Void {
        MediaLocks.run(() -> {
            var image = MediaAsset.query.select(["id", "filename", "title"])
                .where("id", id)
                .where("trashed_epoch", ">", 0)
                .limit(1)
                .first();
            if (image == null) {
                return false;
            }
            var disk = Storage.disk("media");
            if (disk.fileExists(image.filename)) {
                throw new Exception("Another file already uses this image's name.");
            }
            var trashed = trashPath(image.filename);
            var moved = moveFile(disk, trashed, image.filename);
            try {
                DBStatic.transaction(() -> {
                    MediaAsset.query.where("id", image.id).update(["trashed_epoch" => 0]);
                    Activity.record("restored", "media", image.id, image.title);
                });
            } catch (error:Dynamic) {
                if (moved) {
                    disk.move(image.filename, trashed);
                }
                throw error;
            }
            ContentCache.changed("media");
            return true;
        });
    }

    /** Deletes a trashed image and its file permanently. **/
    public static function remove(id:Int):Void {
        MediaLocks.run(() -> erase(id, null));
    }

    /**
        Permanently deletes the images that have been in the trash for 30
        days, and returns how many it deleted.
    **/
    public static function purgeTrash():Int {
        var cutoff = Date.now().getTime() - TRASH_DAYS * DAY_MS;
        var deleted = 0;
        var after = 0;
        while (true) {
            var expired = MediaAsset.query.select(["id"])
                .where("trashed_epoch", ">", 0)
                .where("trashed_epoch", "<=", cutoff)
                .where("id", ">", after)
                .orderBy("id")
                .limit(PURGE_BATCH)
                .get();
            for (image in expired) {
                after = image.id;
                try {
                    if (MediaLocks.run(() -> erase(image.id, cutoff))) {
                        deleted++;
                    }
                } catch (error:Dynamic) {
                    // A referenced image stays in the trash and is checked again on the next run.
                    trace('Image ${image.id} stayed in the trash: ${Std.string(error)}');
                }
            }
            if (expired.length < PURGE_BATCH) {
                break;
            }
        }
        return deleted;
    }

    /**
        Deletes a trashed image. With `expiredBefore`, only an image trashed
        before that time is deleted, and the system records the deletion.
    **/
    static function erase(id:Int, expiredBefore:Null<Float>):Bool {
        Schema.enableForeignKeyConstraints();
        var image = MediaAsset.query.select(["id", "filename", "title", "trashed_epoch"])
            .where("id", id)
            .limit(1)
            .first();
        if (image == null) {
            return false;
        }
        if (image.trashed_epoch <= 0) {
            if (expiredBefore != null) {
                return false;
            }
            throw new Exception("Move this image to the trash before deleting it permanently.");
        }
        if (expiredBefore != null && image.trashed_epoch > expiredBefore) {
            return false;
        }
        if (MediaUsage.used(image.id, image.filename)) {
            throw new Exception(referenced);
        }
        var disk = Storage.disk("media");
        var path = trashPath(image.filename);
        var quarantine = '${TRASH_FOLDER}/.${image.filename}.deleting';
        var moved = moveFile(disk, path, quarantine);
        try {
            DBStatic.transaction(() -> {
                image.delete();
                if (expiredBefore == null) {
                    Activity.record("deleted", "media", image.id, image.title);
                } else {
                    Activity.append(0, "System", "deleted", "media", image.id, image.title);
                }
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
    }

    static function moveFile(disk:StorageDisk, from:String, to:String):Bool {
        if (!disk.fileExists(from)) {
            return false;
        }
        disk.move(from, to);
        return true;
    }
}
