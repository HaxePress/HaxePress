package hx.press;

import hx.press.Pagination.PageCursor;
import hx.press.data.QueryPage;
import hx.well.database.query.QueryBuilder;
import hx.press.model.Category;
import hx.press.model.ContentItem;
#if jvm
import java.NativeString;
import java.util.Locale;
#end

typedef CategorySummary = {
    var id:Int;
    var name:String;
    var items:Int;
}

class CategoryData {
    public static inline var PAGE_SIZE = 20;
    static inline var NAVIGATION_SIZE = 12;
    static inline var OPTION_SIZE = 20;

    public static function normalize(name:String):String {
        return ~/\s+/g.replace(StringTools.trim(name), " ");
    }

    public static function key(name:String):String {
        #if jvm
        var nativeName:NativeString = cast name;
        return nativeName.toLowerCase(Locale.ROOT);
        #else
        return name.toLowerCase();
        #end
    }

    public static function names(selected:String = ""):Array<String> {
        var names:Array<String> = ContentCache.remember("categories", "navigation",
            [NAVIGATION_SIZE], () -> {
                var rows = Category.query.select(["name"])
                    .orderBy("id")
                    .limit(NAVIGATION_SIZE)
                    .get();
                return [for (row in rows) Std.string(row.name)];
            });
        if (selected != "" && !names.contains(selected)) {
            var name:Null<String> = ContentCache.remember("categories", "named", [selected], () -> {
                var row = Category.query.select(["name"]).where("name", selected).limit(1).first();
                return row == null ? null : Std.string(row.name);
            });
            if (name != null)
                names = names.concat([name]);
        }
        return names;
    }

    public static function options(search:String):Array<String> {
        var prefix = key(normalize(search)).substr(0, 80);
        return ContentCache.remember("categories", "options", [prefix, OPTION_SIZE], () -> {
            var query = Category.query.select(["name"]);
            prefixFilter(query, prefix);
            var rows = query.orderBy("name_key").limit(OPTION_SIZE).get();
            return [for (row in rows) Std.string(row.name)];
        });
    }

    static function prefixFilter(query:QueryBuilder<Category>, prefix:String):Void {
        if (prefix != "") {
            query.where("name_key", ">=", prefix);
            query.where("name_key", "<", prefix + String.fromCharCode(0x10FFFF));
        }
    }

    public static function firstName():String {
        return ContentCache.remember("categories", "first", [], () -> {
            var row = Category.query.select(["name"]).orderBy("id").limit(1).first();
            return row == null ? "" : Std.string(row.name);
        });
    }

    public static function count(search:String = ""):Int {
        var prefix = key(normalize(search)).substr(0, 80);
        return ContentCache.remember("categories", "count", [prefix], () -> {
            var query = Category.query.select(["id"]);
            prefixFilter(query, prefix);
            return query.count();
        });
    }

    public static function page(search:String, cursor:Null<PageCursor>):QueryPage<CategorySummary> {
        var prefix = key(normalize(search)).substr(0, 80);
        var contentRevision = ContentCache.revision("items");
        return ContentCache.remember("categories", "manage",
            [prefix, Pagination.token(cursor), PAGE_SIZE, contentRevision], () -> {
                var contentCount = ContentItem.query.selectCount()
                    .whereColumn("content_items.category", "categories.name");
                var query = Category.query.select(["id", "name"]).selectSub(contentCount, "items");
                prefixFilter(query, prefix);
                if (cursor != null)
                    query.where("id", cursor.before ? "<" : ">", cursor.id);
                var direction = cursor != null && cursor.before ? "DESC" : "ASC";
                var rows:Array<CategorySummary> = [
                    for (row in query.orderBy("id", direction).limit(PAGE_SIZE + 1).get())
                        (cast row.toObject() : CategorySummary)
                ];
                return Pagination.slice(rows, PAGE_SIZE, cursor);
            });
    }
}
