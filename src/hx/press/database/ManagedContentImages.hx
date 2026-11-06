package hx.press.database;

import hx.press.media.MediaReferences;
import hx.press.MediaStorage;
import hx.press.ContentCache;
import hx.well.facades.Storage;
import hx.well.database.Connection;
import hx.press.model.ContentItem;
import hx.press.model.Setting;

/** Import the original sample covers without changing article text or edit dates. */
class ManagedContentImages {
    public static function run():Void {
        if (Setting.query.where("key", "managed_content_images_v1").exists()) {
            Connection.free();
            return;
        }
        var imported:Map<String, String> = new Map();
        var changed = false;
        var after = 0;
        while (true) {
            var items = ContentItem.query.select(["id", "image"])
                .where("image", "LIKE", "/images/%")
                .where("id", ">", after)
                .orderBy("id")
                .limit(100)
                .get();
            if (items.length == 0)
                break;
            for (item in items) {
                var source = item.image;
                if (source == null
                    || !~/^\/images\/[A-Za-z0-9_-]+\.(jpg|jpeg|png|gif)$/.match(source))
                    continue;
                if (!imported.exists(source)) {
                    var bytes = Storage.disk("public").getBytes(source.substr(1));
                    var format = MediaStorage.format(bytes);
                    var dimensions = MediaStorage.dimensions(bytes);
                    if (format == null || dimensions == null
                        || bytes.length > MediaReferences.MAX_BYTES)
                        throw 'Cannot import the existing post image: ${source}';
                    imported.set(source, MediaStorage.save(bytes, format, dimensions).url);
                }
                item.update(["image" => imported.get(source)]);
                changed = true;
            }
            after = items[items.length - 1].id;
        }
        Setting.query.insert(["key" => "managed_content_images_v1", "value" => "1"]);
        Connection.free();
        if (changed)
            ContentCache.contentChanged();
    }
}
