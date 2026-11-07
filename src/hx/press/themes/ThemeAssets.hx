package hx.press.themes;

import haxe.Exception;
import haxe.Json;
import haxe.crypto.Sha256;
import haxe.io.Bytes;
import hx.press.ContentCache;
import hx.press.Pagination;
import hx.press.Pagination.PageCursor;
import hx.press.SiteSettingsStore;
import hx.press.data.QueryPage;
import hx.press.media.MediaReferences;
import hx.press.model.ThemeAsset;
import hx.press.model.ThemeDesign;
import hx.well.facades.Storage;
import hx.well.internal.SecureToken;
import hx.well.thread.MutexPool;

typedef ThemeAssetRecord = {
    var id:Int;
    var filename:String;
    var title:String;
    var alt:String;
    var mime_type:String;
    var width:Int;
    var height:Int;
    var size:Int;
}

typedef ThemeImageInfo = {
    var extension:String;
    var contentType:String;
    var width:Int;
    var height:Int;
    var sha256:String;
}

class ThemeAssets {
    public static inline var PAGE_SIZE = 24;
    public static inline var MAX_ASSETS = 128;
    public static inline var MAX_TOTAL_BYTES = 62 * 1024 * 1024;
    public static final locks = new MutexPool();
    static final columns = ["id", "filename", "title", "alt", "mime_type", "width", "height", "size"];

    public static function validThemeId(id:String):Bool {
        return id != null && id.length <= 80 && ~/^theme-[a-z0-9]+(?:-[a-z0-9]+)*$/.match(id);
    }

    public static function prefix(id:String):String {
        if (!validThemeId(id)) {
            throw new Exception("Choose a valid theme.");
        }
        return '/theme-assets/${id}/';
    }

    public static function url(id:String, filename:String):String {
        return '${prefix(id)}${filename}';
    }

    public static function validFilename(filename:String):Bool {
        return filename != null && ~/^ta_[A-Za-z0-9_-]{32}\.(jpg|png|webp|gif)$/.match(filename);
    }

    public static function packagedFilename(filename:String):String {
        if (validFilename(filename)) {
            return filename;
        }
        var hash = Sha256.encode('theme-asset:${filename}').substr(0, 32);
        return 'ta_${hash}${filename.substr(32)}';
    }

    public static function imageUrl(value:String):Bool {
        return value != null
            && ~/^\/theme-assets\/theme-[a-z0-9]+(?:-[a-z0-9]+)*\/ta_[A-Za-z0-9_-]{32}\.(jpg|png|webp|gif)(?![\s\S])/.match(value);
    }

    public static function rules(id:String):Dynamic {
        var rules:Dynamic = MediaReferences.rules();
        rules.uploadUrl = '/admin/themes/${id}/assets';
        rules.imagePattern = '^(?:/media/[A-Za-z0-9_-]{32}|${prefix(id)}ta_[A-Za-z0-9_-]{32})\\.(jpg|png|webp|gif)$$';
        return rules;
    }

    static function domain(id:String):String {
        return 'theme-assets:${id}';
    }

    public static function changed(id:String):Void {
        ContentCache.changed(domain(id));
    }

    public static function locked<T>(id:String, work:Void->T):T {
        locks.acquire(id);
        try {
            var result = work();
            locks.release(id);
            return result;
        } catch (error:Dynamic) {
            locks.release(id);
            throw error;
        }
    }

    public static function saveImage(id:String, bytes:Bytes, info:ThemeImageInfo,
            title:String = "", alt:String = ""):Dynamic {
        return locked(id, () -> {
            if (!validThemeId(id) || !ThemeDesign.query.where("id", id).exists()) {
                throw new Exception("This theme is no longer available.");
            }
            requireBudget(id, 1, bytes.length);
            var disk = Storage.disk("theme_assets");
            var filename = 'ta_${SecureToken.generate(32)}.${info.extension}';
            var path = '${id}/${filename}';
            disk.put(path, bytes);
            var registered = false;
            try {
                var assetId = ThemeAsset.query.insert([
                    "theme_id" => id,
                    "filename" => filename,
                    "title" => title == "" ? filename : title.substr(0, 180),
                    "alt" => alt.substr(0, 500),
                    "mime_type" => info.contentType,
                    "width" => info.width,
                    "height" => info.height,
                    "size" => bytes.length,
                    "sha256" => info.sha256,
                    "created_at" => SiteSettingsStore.timestamp()
                ]);
                registered = true;
                changed(id);
                return {
                    id: assetId,
                    filename: filename,
                    url: url(id, filename),
                    contentType: info.contentType,
                    width: info.width,
                    height: info.height,
                    size: bytes.length
                };
            } catch (error:Dynamic) {
                if (!registered) {
                    disk.delete(path);
                }
                throw error;
            }
        });
    }

    public static function requireBudget(id:String, additionalFiles:Int = 0,
            additionalBytes:Int = 0):Void {
        var count = ThemeAsset.query.where("theme_id", id).count();
        var total = ThemeAsset.query.where("theme_id", id).sum("size");
        if (count + additionalFiles > MAX_ASSETS || total + additionalBytes > MAX_TOTAL_BYTES) {
            throw new Exception("The theme image library exceeds its export package budget. Remove unused images before adding more.");
        }
    }

    public static function page(id:String, search:String,
            cursor:Null<PageCursor>):QueryPage<ThemeAssetRecord> {
        return ContentCache.remember(domain(id), "library",
            [search, Pagination.token(cursor), PAGE_SIZE], () -> {
                var query = ThemeAsset.query.select(columns).where("theme_id", id);
                if (search != "") {
                    var escaped = StringTools.replace(StringTools.replace(StringTools.replace(search,
                        "!", "!!"), "%", "!%"),
                        "_", "!_");
                    query.whereLike("title", '%${escaped}%');
                }
                if (cursor != null) {
                    query.where("id", cursor.before ? ">" : "<", cursor.id);
                }
                var direction = cursor != null && cursor.before ? "ASC" : "DESC";
                var rows:Array<ThemeAssetRecord> = query.orderBy("id", direction)
                    .limit(PAGE_SIZE + 1)
                    .get()
                    .map(model -> cast model.toObject());
                return Pagination.slice(rows, PAGE_SIZE, cursor);
            });
    }

    public static function count(id:String, search:String):Int {
        return ContentCache.remember(domain(id), "count", [search], () -> {
            var query = ThemeAsset.query.where("theme_id", id);
            if (search != "") {
                var escaped = StringTools.replace(StringTools.replace(StringTools.replace(search,
                    "!", "!!"), "%", "!%"), "_",
                    "!_");
                query.whereLike("title", '%${escaped}%');
            }
            return query.count();
        });
    }

    public static function find(id:String,
            filename:String):Null<{filename:String, mime_type:String}> {
        return ContentCache.remember(domain(id), "image", [filename], () -> {
            var model = ThemeAsset.query.select(["filename", "mime_type"])
                .where("theme_id", id)
                .where("filename", filename)
                .limit(1)
                .first();
            return model == null ? null : cast model.toObject();
        });
    }

    public static function references(document:Dynamic):Map<String, String> {
        var found:Map<String, String> = [];
        var source = Json.stringify(document);
        var pattern = ~/\/theme-assets\/(theme-[a-z0-9]+(?:-[a-z0-9]+)*)\/(ta_[A-Za-z0-9_-]{32}\.(?:jpg|png|webp|gif))/g;
        var offset = 0;
        while (pattern.matchSub(source, offset)) {
            found.set(pattern.matched(0), pattern.matched(1));
            var position = pattern.matchedPos();
            offset = position.pos + position.len;
        }
        return found;
    }

    public static function requireDesign(id:String, document:Dynamic):Void {
        var addresses = references(document);
        var filenames = [];
        for (address => owner in addresses) {
            if (owner != id) {
                throw new Exception("Choose images owned by this theme.");
            }
            filenames.push(address.substr(prefix(id).length));
        }
        if (filenames.length == 0) {
            return;
        }
        var available = ThemeAsset.query.select(["filename"])
            .where("theme_id", id)
            .whereIn("filename", cast filenames)
            .limit(filenames.length)
            .get()
            .map(asset -> asset.filename);
        if (available.length != filenames.length) {
            throw new Exception("A theme image is no longer available.");
        }
        var disk = Storage.disk("theme_assets");
        for (filename in available) {
            if (!disk.fileExists('${id}/${filename}')) {
                throw new Exception("A theme image file is missing.");
            }
        }
    }

    public static function used(id:String):Map<String, Bool> {
        var model = ThemeDesign.query.select(["draft", "published"])
            .where("id", id)
            .limit(1)
            .first();
        var result:Map<String, Bool> = [];
        if (model != null) {
            for (source in [model.draft, model.published]) {
                if (source != "") {
                    var document:Dynamic = Json.parse(source);
                    for (address => _ in references(document)) {
                        result.set(address, true);
                    }
                }
            }
        }
        return result;
    }

    public static function remove(id:String, assetId:Int):Void {
        locked(id, () -> {
            var asset = ThemeAsset.query.select(["id", "filename"])
                .where("theme_id", id)
                .where("id", assetId)
                .limit(1)
                .first();
            if (asset == null) {
                return false;
            }
            if (used(id).exists(url(id, asset.filename))) {
                throw new Exception("Remove this image from the draft and published design before deleting it.");
            }
            var disk = Storage.disk("theme_assets");
            var path = '${id}/${asset.filename}';
            var quarantine = '${id}/.${asset.filename}.deleting';
            var exists = disk.fileExists(path);
            if (exists) {
                disk.move(path, quarantine);
            }
            try {
                asset.delete();
            } catch (error:Dynamic) {
                if (exists) {
                    disk.move(quarantine, path);
                }
                throw error;
            }
            if (exists) {
                disk.delete(quarantine);
            }
            changed(id);
            return true;
        });
    }
}
