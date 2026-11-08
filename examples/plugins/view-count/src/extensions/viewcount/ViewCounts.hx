package extensions.viewcount;

import hx.press.Pagination;
import hx.press.Pagination.PageCursor;
import hx.press.content.ContentTypes;
import hx.press.data.QueryPage;
import hx.press.i18n.I18n;
import hx.press.model.ContentItem;
import hx.press.plugins.PluginDatabase;
import hx.press.plugins.PluginMigration;

typedef ViewTotalRecord = {
    var id:Int;
    var content_id:Int;
    var views:Int;
}

/** A counted content item with what the administration shows of it. **/
typedef ViewedContent = {
    var id:Int;
    var contentId:Int;
    var title:String;
    var type:String;
    var collection:String;
    var url:String;
    var views:Int;
}

/** The plugin's tables: counted views per content item, and per country when that is on. **/
class ViewCounts {
    public static inline var SLUG = "view-count";
    public static inline var PAGE_SIZE = 30;
    public static inline var MAX_LIMIT = 100;

    public static function migrate():Void {
        var database = new PluginDatabase(SLUG);
        var schema = database.schema();
        var totals = database.tableName("totals");
        var countries = database.tableName("countries");
        database.migrate([
            new PluginMigration("001_create_totals", () -> {
                if (!schema.hasTable(totals)) {
                    schema.create(totals, table -> {
                        table.id();
                        table.integer("content_id").unique();
                        table.integer("views");
                        table.foreign("content_id")
                            .references("id")
                            .on("content_items")
                            .cascadeOnDelete();
                    });
                }
            }),
            new PluginMigration("002_create_countries", () -> {
                if (!schema.hasTable(countries)) {
                    schema.create(countries, table -> {
                        table.id();
                        table.integer("content_id");
                        table.string("country", 7);
                        table.integer("views");
                        table.unique(["content_id", "country"]);
                        table.index(["country", "views"]);
                        table.foreign("content_id")
                            .references("id")
                            .on("content_items")
                            .cascadeOnDelete();
                    });
                }
            }),
            // Content lists sort by the Views column, and the plugin's page lists the most viewed.
            new PluginMigration("003_index_total_views", () -> {
                schema.table(totals, table -> {
                    table.index(["views", "content_id"]);
                });
            })
        ]);
    }

    /**
        Adds counted views: one keyed increment per content item, for the
        items that still exist.
    **/
    public static function add(views:Array<Dynamic>):Void {
        var counts:Map<Int, Int> = [];
        for (view in views) {
            var id:Int = view.content.id;
            var count:Int = view.count;
            var previous = counts.get(id) ?? 0;
            counts.set(id, previous + count);
        }
        var ids:Array<Dynamic> = [for (id in counts.keys()) id];
        if (ids.length == 0) {
            return;
        }
        var existing = ContentItem.query.select(["id"]).whereIn("id", ids).get();
        for (item in existing) {
            var count = counts.get(item.id) ?? 0;
            ViewTotal.query.upsertIncrement(["content_id" => item.id, "views" => count],
                ["content_id"], ["views"]);
        }
    }

    /** The counted views of the content item `id`. **/
    public static function forContent(id:Int):Int {
        var row = ViewTotal.query.select(["views"]).where("content_id", id).limit(1).first();
        return row == null ? 0 : row.views;
    }

    /** How many content items have counted views. **/
    public static function count():Int {
        return ViewTotal.query.count();
    }

    /** The counted views of all content. **/
    public static function total():Float {
        return ViewTotal.query.select(["views"]).sum("views");
    }

    /** Content items by counted views, most viewed first, `limit` at a time. **/
    public static function page(cursor:Null<PageCursor>, limit:Int):QueryPage<ViewTotalRecord> {
        var query = ViewTotal.query.select(["id", "content_id", "views"]);
        if (cursor != null) {
            var views = Std.parseInt(cursor.value ?? "") ?? 0;
            var id:Int = cursor.id;
            // Before the cursor come more views, or as many with a larger ID.
            var comparison = cursor.before ? ">" : "<";
            query.where(matches -> {
                matches.where("views", comparison, views).orWhere(sameViews -> {
                    sameViews.where("views", views).where("id", comparison, id);
                });
            });
        }
        var direction = cursor != null && cursor.before ? "ASC" : "DESC";
        var rows:Array<ViewTotalRecord> = [
            for (row in query.orderBy("views", direction)
                .orderBy("id", direction)
                .limit(limit + 1)
                .get())
                (cast row.toObject() : ViewTotalRecord)
        ];
        return Pagination.slice(rows, limit, cursor);
    }

    /** The counted views of one content item as a page of one row, or of none. **/
    public static function single(contentId:Int):QueryPage<ViewTotalRecord> {
        var rows:Array<ViewTotalRecord> = [
            for (row in ViewTotal.query.select(["id", "content_id", "views"])
                .where("content_id", contentId)
                .limit(1)
                .get())
                (cast row.toObject() : ViewTotalRecord)
        ];
        return {items: rows, hasMore: false};
    }

    /** The titles, collections and public addresses of the counted items on a page. **/
    public static function describe(records:Array<ViewTotalRecord>):Array<ViewedContent> {
        var ids:Array<Dynamic> = [for (record in records) record.content_id];
        var items:Map<Int, ContentItem> = [];
        if (ids.length > 0) {
            for (item in ContentItem.query.select(["id", "title", "slug", "status", "content_type"])
                .whereIn("id", ids)
                .get()) {
                items.set(item.id, item);
            }
        }
        var result:Array<ViewedContent> = [];
        for (record in records) {
            var item = items.get(record.content_id);
            var kind = item == null ? "" : item.content_type;
            var type = item == null ? null : ContentTypes.find(kind);
            var published = item != null
                && item.status == "published"
                && type != null
                && type.publicVisible;
            var slug = item == null ? "" : StringTools.urlEncode(item.slug);
            var title = item == null ? '#${record.content_id}' : item.title;
            var base = type == null ? "" : type.publicBase;
            result.push({
                id: record.id,
                contentId: record.content_id,
                title: title,
                type: kind,
                collection: type == null ? kind : type.name,
                url: published ? '${base}/${slug}' : "",
                views: record.views
            });
        }
        return result;
    }

    /** `value` with the thousands separator of the current language. **/
    public static function format(value:Float):String {
        var digits = Std.string(Math.ffloor(Math.max(0, value)));
        var dot = digits.indexOf(".");
        if (dot >= 0) {
            digits = digits.substr(0, dot);
        }
        var separator = I18n.locale() == "tr" ? "." : ",";
        var grouped = new StringBuf();
        for (index in 0...digits.length) {
            if (index > 0 && (digits.length - index) % 3 == 0) {
                grouped.add(separator);
            }
            grouped.add(digits.charAt(index));
        }
        return grouped.toString();
    }
}
