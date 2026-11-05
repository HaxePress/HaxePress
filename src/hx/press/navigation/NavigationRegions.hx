package hx.press.navigation;

import haxe.Exception;
import hx.press.ContentCache;
import hx.press.content.ContentLocks;
import hx.press.model.MenuLink;
import hx.press.model.NavigationRegion;
import hx.well.facades.Schema;

typedef NavigationRegionRecord = {
    var key:String;
    var name:String;
    var max_links:Int;
    var enabled:Int;
    var system:Int;
}

class NavigationRegions {
    static final columns = ["key", "name", "max_links", "enabled", "system"];

    public static function initialize():Void {
        if (!Schema.hasTable("navigation_regions")) {
            Schema.create("navigation_regions", table -> {
                table.string("key", 40).primary();
                table.string("name", 100);
                table.integer("max_links").defaultValue(12);
                table.integer("enabled").defaultValue(1);
                table.integer("system").defaultValue(0);
            });
        }
        ensure("header", "Header menu", 12, true);
        ensure("footer", "Footer menu", 12, true);
        if (Schema.hasColumn("menu_links", "page_id")) {
            Schema.table("menu_links", table -> table.renameColumn("page_id", "content_id"));
        }
        if (!Schema.hasColumn("menu_links", "collection_key")) {
            Schema.table("menu_links",
                table -> table.string("collection_key", 32).defaultValue(""));
        }
    }

    public static function validKey(key:String):Bool {
        return key != null && ~/^[a-z][a-z0-9_-]{0,39}$/.match(key);
    }

    public static function find(key:String):Null<NavigationRegionRecord> {
        if (!validKey(key)) {
            return null;
        }
        return ContentCache.remember("navigation", "region", [key], () -> {
            var region = NavigationRegion.query.select(columns).where("key", key).first();
            return region == null ? null : cast region.toObject();
        });
    }

    public static function ensure(key:String, name:String, maximum:Int = 12,
            system:Bool = false):Void {
        if (NavigationRegion.query.where("key", key).exists()) {
            return;
        }
        if (!validKey(key) || name == "" || name.length > 100 || maximum < 1 || maximum > 50) {
            throw new Exception("Choose a navigation region key, label and a limit from 1 to 50.");
        }
        NavigationRegion.query.create([
            "key" => key,
            "name" => name,
            "max_links" => maximum,
            "enabled" => 1,
            "system" => system ? 1 : 0
        ]);
        ContentCache.changed("navigation");
    }

    public static function options(search:String = "",
            selected:String = ""):Array<NavigationRegionRecord> {
        var rows:Array<NavigationRegionRecord> = ContentCache.remember("navigation",
            "region-options", [search, 20], () -> {
                var query = NavigationRegion.query.select(columns);
                if (search != "") {
                    var pattern = "%"
                        + StringTools.replace(StringTools.replace(StringTools.replace(search, "!",
                            "!!"), "%", "!%"),
                            "_", "!_")
                        + "%";
                    query.whereLike("name", pattern);
                }
                return query.orderBy("key").limit(20).get().map(model -> cast model.toObject());
            });
        var known = false;
        for (row in rows) {
            if (row.key == selected) {
                known = true;
                break;
            }
        }
        if (!known && selected != "") {
            var extra = find(selected);
            if (extra != null) {
                rows = rows.concat([extra]);
            }
        }
        return rows;
    }

    public static function save(key:String, name:String, maximum:Int, enabled:Bool):Void {
        ContentLocks.run("navigation", () -> {
            var current = find(key);
            if (current == null) {
                ensure(key, name, maximum);
            } else {
                if (name == ""
                    || name.length > 100
                    || maximum < 1
                    || maximum > 50
                    || MenuLink.query.where("location", key).count() > maximum) {
                    throw new Exception("The region limit must fit its existing links and stay between 1 and 50.");
                }
                NavigationRegion.query.where("key", key)
                    .update(["name" => name, "max_links" => maximum, "enabled" => enabled ? 1 : 0]);
                ContentCache.changed("navigation");
            }
            return true;
        });
    }
}
