package extensions.viewcount;

import hx.press.i18n.Languages;
import hx.press.Pagination;
import hx.press.Pagination.PageCursor;
import hx.press.content.ContentTypes;
import hx.press.content.ContentViews;
import hx.press.data.QueryPage;
import hx.press.model.ContentItem;
import hx.press.model.InstalledPackage;
import hx.well.database.query.QueryBuilder;

typedef CountryViewRecord = {
    var id:Int;
    var content_id:Int;
    var country:String;
    var views:Int;
}

/** The rows a page or the data endpoint lists: one content item, one country, or all. **/
typedef CountryViewFilter = {
    var content:Null<Int>;
    var country:Null<String>;
}

/** A counted row with what the administration shows of its content item. **/
typedef CountryViewEntry = {
    var id:Int;
    var contentId:Int;
    var title:String;
    var type:String;
    var url:String;
    var country:String;
    var views:Int;
}

/** Counted views per content item and country, kept while the plugin's country setting is on. **/
class CountryViewData {
    public static inline var PAGE_SIZE = 30;
    public static inline var MAX_LIMIT = 100;

    /** What a view without a trusted country counts as. **/
    public static inline var UNKNOWN = "UNKNOWN";

    /** The package that provides the visitor's country. **/
    public static inline var COUNTRY_SOURCE = "plugin-cloudflare";

    /** Whether the Cloudflare plugin, which provides the visitor's country, is active. **/
    public static function countrySourceActive():Bool {
        return InstalledPackage.query.where("id", COUNTRY_SOURCE).where("enabled", 1).exists();
    }

    /** A country filter or stored country: two uppercase letters or `UNKNOWN`. **/
    public static function validCountry(code:Null<String>):Bool {
        return code == UNKNOWN || ContentViews.validCountry(code);
    }

    /**
        Adds counted views: one keyed increment per content item and
        country, for the items that still exist.
    **/
    public static function add(views:Array<Dynamic>):Void {
        var counts:Map<String, Int> = [];
        var contents:Map<String, Int> = [];
        var countries:Map<String, String> = [];
        for (view in views) {
            var id:Int = view.content.id;
            var reported:String = view.country;
            var country = validCountry(reported) ? reported : UNKNOWN;
            var count:Int = view.count;
            var key = '${id}:${country}';
            var previous = counts.get(key) ?? 0;
            counts.set(key, previous + count);
            contents.set(key, id);
            countries.set(key, country);
        }
        var ids:Array<Dynamic> = [for (id in contents) id];
        if (ids.length == 0) {
            return;
        }
        var existing:Map<Int, Bool> = [];
        for (item in ContentItem.query.select(["id"]).whereIn("id", ids).get()) {
            existing.set(item.id, true);
        }
        for (key => count in counts) {
            var id:Int = contents.get(key) ?? 0;
            if (!existing.exists(id)) {
                continue;
            }
            var row:Map<String,
                Dynamic> = ["content_id" => id, "country" => countries.get(key), "views" => count];
            CountryView.query.upsertIncrement(row, ["content_id", "country"], ["views"]);
        }
    }

    static function filtered(filter:CountryViewFilter):QueryBuilder<CountryView> {
        var query = CountryView.query.select(["id", "content_id", "country", "views"]);
        if (filter.content != null) {
            query.where("content_id", filter.content);
        }
        if (filter.country != null) {
            query.where("country", filter.country);
        }
        return query;
    }

    /** How many rows match `filter`. **/
    public static function count(filter:CountryViewFilter):Int {
        return filtered(filter).count();
    }

    /** The rows matching `filter`, most views first, `limit` at a time. **/
    public static function page(filter:CountryViewFilter, cursor:Null<PageCursor>,
            limit:Int):QueryPage<CountryViewRecord> {
        var query = filtered(filter);
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
        var rows:Array<CountryViewRecord> = [
            for (row in query.orderBy("views", direction)
                .orderBy("id", direction)
                .limit(limit + 1)
                .get())
                (cast row.toObject() : CountryViewRecord)
        ];
        return Pagination.slice(rows, limit, cursor);
    }

    /** The cursor of the next page after `page`, or null. **/
    public static function next(page:QueryPage<CountryViewRecord>,
            cursor:Null<PageCursor>):Null<String> {
        var hasNext = cursor == null ? page.hasMore : cursor.before || page.hasMore;
        if (!hasNext || page.items.length == 0) {
            return null;
        }
        var last = page.items[page.items.length - 1];
        return Pagination.token({id: last.id, value: Std.string(last.views), before: false});
    }

    /** The title of the content item `id`, or null when it does not exist. **/
    public static function title(id:Int):Null<String> {
        var item = ContentItem.query.select(["title"]).where("id", id).limit(1).first();
        return item == null ? null : item.title;
    }

    /** The titles and public addresses of the content items on a page. **/
    public static function describe(records:Array<CountryViewRecord>):Array<CountryViewEntry> {
        var ids:Array<Dynamic> = [for (record in records) record.content_id];
        var items:Map<Int, ContentItem> = [];
        if (ids.length > 0) {
            for (item in ContentItem.query.select(["id", "title", "slug", "status", "content_type", "language"])
                .whereIn("id", ids)
                .get()) {
                items.set(item.id, item);
            }
        }
        var result:Array<CountryViewEntry> = [];
        for (record in records) {
            var item = items.get(record.content_id);
            var kind = item == null ? "" : item.content_type;
            var type = item == null ? null : ContentTypes.find(kind);
            var published = item != null
                && item.status == "published"
                && type != null
                && type.publicVisible;
            var slug = item == null ? "" : StringTools.urlEncode(item.slug);
            var base = type == null ? "" : type.publicBase;
            result.push({
                id: record.id,
                contentId: record.content_id,
                title: item == null ? '#${record.content_id}' : item.title,
                type: kind,
                url: published ? Languages.path(item.language, '${base}/${slug}') : "",
                country: record.country,
                views: record.views
            });
        }
        return result;
    }
}
