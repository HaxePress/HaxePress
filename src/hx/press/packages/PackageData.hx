package hx.press.packages;

import hx.press.CategoryData;
import hx.press.ContentCache;
import hx.press.Pagination;
import hx.press.Pagination.PageCursor;
import hx.press.data.QueryPage;
import hx.well.database.query.QueryBuilder;
import hx.press.model.InstalledPackage;

typedef PackageRecord = {
    var id:String;
    var kind:String;
    var slug:String;
    var name:String;
    var version:String;
    var directory:String;
    var manifest:String;
    var settings:String;
    var enabled:Int;
    var restart_required:Int;
}

typedef PackageSummary = {
    var id:String;
    var kind:String;
    var slug:String;
    var name:String;
    var version:String;
    var description:String;
    var author:String;
    var last_error:String;
    var enabled:Int;
    var setting_count:Int;
    var restart_required:Int;
    var updated_at:String;
}

class PackageData {
    public static inline var PAGE_SIZE = 12;
    public static inline var MAX_ACTIVE_PLUGINS = 32;
    static final runtimeColumns = [
        "id",
        "kind",
        "slug",
        "name",
        "version",
        "directory",
        "manifest",
        "settings",
        "enabled",
        "restart_required"
    ];
    static final summaryColumns = [
        "id",
        "kind",
        "slug",
        "name",
        "version",
        "description",
        "author",
        "last_error",
        "enabled",
        "setting_count",
        "restart_required",
        "updated_at"
    ];

    static function filter(query:QueryBuilder<InstalledPackage>, kind:String, search:String):Void {
        query.where("kind", kind);
        if (search != "") {
            var prefix = CategoryData.key(CategoryData.normalize(search));
            query.where("name_key", ">=", prefix)
                .where("name_key", "<", '${prefix}${String.fromCharCode(0x10FFFF)}');
        }
    }

    public static function page(kind:String, search:String,
            cursor:Null<PageCursor>):QueryPage<PackageSummary> {
        var cacheName = kind == "theme" ? "manage-built-in-first" : "manage";
        return ContentCache.remember("extensions", cacheName,
            [kind, search, Pagination.token(cursor), PAGE_SIZE], () -> {
                var builtInCursor = kind == "theme" && cursor != null
                    && cursor.id == BuiltInTheme.ID;
                if (builtInCursor && cursor.before) {
                    return {items: [], hasMore: false};
                }
                var pinned = kind == "theme" && cursor == null ? builtInSummary(search) : null;
                var query = InstalledPackage.query.select(summaryColumns);
                filter(query, kind, search);
                if (kind == "theme") {
                    query.where("id", "!=", BuiltInTheme.ID);
                }
                if (cursor != null && !builtInCursor) {
                    query.where("id", cursor.before ? "<" : ">", cursor.id);
                }
                var direction = cursor != null && cursor.before ? "DESC" : "ASC";
                var limit = PAGE_SIZE + 1 - (pinned == null ? 0 : 1);
                var rows:Array<PackageSummary> = [
                    for (row in query.orderBy("id", direction).limit(limit).get())
                        (cast row.toObject() : PackageSummary)
                ];
                if (pinned != null) {
                    rows.unshift(pinned);
                } else if (kind == "theme"
                    && cursor != null
                    && cursor.before
                    && rows.length <= PAGE_SIZE) {
                    // The built-in row precedes every ordinary ID in the reverse cursor order.
                    var previous = builtInSummary(search);
                    if (previous != null) {
                        rows.push(previous);
                    }
                }
                return Pagination.slice(rows, PAGE_SIZE, cursor);
            });
    }

    static function builtInSummary(search:String):Null<PackageSummary> {
        var query = InstalledPackage.query.select(summaryColumns);
        filter(query, "theme", search);
        var row = query.where("id", BuiltInTheme.ID).limit(1).first();
        return row == null ? null : cast row.toObject();
    }

    public static function count(kind:String, search:String):Int {
        return ContentCache.remember("extensions", "count", [kind, search], () -> {
            var query = InstalledPackage.query.select(["id"]);
            filter(query, kind, search);
            return query.count();
        });
    }

    public static function one(id:String):Null<PackageRecord> {
        return ContentCache.remember("extensions", "package", [id], () -> {
            var row = InstalledPackage.query.select(runtimeColumns)
                .where("id", id)
                .limit(1)
                .first();
            return row == null ? null : cast row.toObject();
        });
    }

    public static function activeDirectory(id:String):Null<String> {
        return ContentCache.remember("extensions", "active-directory", [id], () -> {
            var row = InstalledPackage.query.select(["directory"])
                .where("id", id)
                .where("enabled", 1)
                .first();
            return row == null ? null : row.directory;
        });
    }

    public static function forEvent(event:String, kind:String = ""):Array<PackageRecord> {
        return ContentCache.remember("extensions", "event", [event, kind, MAX_ACTIVE_PLUGINS + 1],
            () -> {
                var columns = [
                    for (column in runtimeColumns)
                        'cms_packages.${column} AS ${column}'
                ];
                var query = InstalledPackage.query.select(columns)
                    .innerJoin("package_hooks", "cms_packages.id", "=", "package_hooks.package_id")
                    .where("cms_packages.enabled", 1)
                    .where("package_hooks.event", event);
                if (kind != "") {
                    query.where("cms_packages.kind", kind);
                }
                return [
                    for (row in query.orderBy("cms_packages.id")
                        .limit(MAX_ACTIVE_PLUGINS + 1)
                        .get())
                        (cast row.toObject() : PackageRecord)
                ];
            });
    }

    public static function activeTheme():Null<PackageRecord> {
        return ContentCache.remember("extensions", "active-theme", [], () -> {
            var row = InstalledPackage.query.select(runtimeColumns)
                .where("kind", "theme")
                .where("enabled", 1)
                .limit(1)
                .first();
            return row == null ? null : cast row.toObject();
        });
    }

    public static function enabledBatch(after:String):Array<PackageRecord> {
        var query = InstalledPackage.query.select(runtimeColumns).where("enabled", 1);
        if (after != "") {
            query.where("id", ">", after);
        }
        return [
            for (row in query.orderBy("id").limit(32).get())
                (cast row.toObject() : PackageRecord)
        ];
    }
}
