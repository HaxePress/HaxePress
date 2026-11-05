package hx.press.database;

import hx.press.ContentCache;
import hx.press.ContentItemData;
import hx.well.database.Connection;
import hx.well.facades.Schema;
import hx.press.model.ContentItem;
import hx.press.model.Setting;

class QueryMetadata {
    static inline var BACKFILL_BATCH_SIZE = 100;

    public static function run():Void {
        if (!Schema.hasColumn("content_items", "reading_minutes")) {
            Schema.table("content_items",
                table -> table.integer("reading_minutes").defaultValue(0));
        }
        if (Setting.query.find("query_metadata_v1") == null) {
            backfillReadingTime();
            Setting.query.create(["key" => "query_metadata_v1", "value" => "1"]);
            ContentCache.contentChanged();
        }
        var indexes = [
            "content_items_status_date_cursor" => ["status", "published_at", "id"],
            "content_items_status_category_date_cursor" =>
            ["status", "category", "published_at", "id"],
            "content_items_featured_date_cursor" => ["status", "featured", "published_at", "id"],
            "content_items_updated_cursor" => ["updated_at", "id"],
            "content_items_status_updated_cursor" => ["status", "updated_at", "id"],
            "content_items_category_lookup" => ["category"]
        ];
        for (name => columns in indexes) {
            if (!Schema.hasIndex("content_items", name))
                Schema.table("content_items", table -> table.index(columns, name));
        }
        Connection.free();
    }

    static function backfillReadingTime():Void {
        var after = 0;
        while (true) {
            var items = ContentItem.query.select(["id", "content"])
                .where("reading_minutes", 0)
                .where("id", ">", after)
                .orderBy("id")
                .limit(BACKFILL_BATCH_SIZE)
                .get();
            if (items.length == 0) {
                break;
            }
            for (item in items) {
                var readingMinutes = ContentItemData.readingMinutes(item.content);
                ContentItem.query.where("id", item.id)
                    .where("reading_minutes", 0)
                    .update(["reading_minutes" => readingMinutes]);
                after = item.id;
            }
        }
    }
}
