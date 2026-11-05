package hx.press;

import hx.press.content.ContentTypes;
import hx.press.model.MenuLink;
import hx.press.model.Setting;
import hx.press.navigation.NavigationRegions;
import hx.well.facades.DBStatic;

typedef NavigationLink = {
    var id:Int;
    var label:String;
    var url:String;
    var new_tab:Int;
}

typedef NavigationSource = {
    > NavigationLink,
    var content_id:Int;
    var collection_key:String;
    var content_slug:Null<String>;
    var content_type:Null<String>;
}

class NavigationData {
    public static inline var MAX_LINKS = 12;

    public static function ensure():Void {
        if (Setting.query.find("cms_navigation_v1") != null) {
            return;
        }
        DBStatic.transaction(() -> {
            for (location in ["header", "footer"]) {
                var position = 0;
                for (link in [
                    {label: "Home", url: "/", collection: ""},
                    {label: "Content", url: "/content", collection: "entry"},
                    {label: "About", url: "/about", collection: ""}
                ]) {
                    MenuLink.query.create([
                        "location" => location,
                        "label" => link.label,
                        "url" => link.url,
                        "position" => position++,
                        "new_tab" => 0,
                        "content_id" => 0,
                        "collection_key" => link.collection,
                        "created_at" => SiteSettingsStore.timestamp(),
                        "updated_at" => SiteSettingsStore.timestamp()
                    ]);
                }
            }
            Setting.query.create(["key" => "cms_navigation_v1", "value" => "1"]);
        });
        ContentCache.changed("navigation");
    }

    public static function links(location:String):Array<NavigationLink> {
        var region = NavigationRegions.find(location);
        if (region == null || region.enabled != 1) {
            return [];
        }
        var contentRevision = ContentCache.revision("items");
        var records:Array<NavigationSource> = ContentCache.remember("navigation", "location",
            [location, region.max_links, contentRevision, ContentTypes.revision()], () -> {
                var archiveKeys = ContentTypes.publicKeys().where("has_archive", 1);
                return MenuLink.query.select([
                    "menu_links.id AS id",
                    "menu_links.label AS label",
                    "menu_links.url AS url",
                    "menu_links.new_tab AS new_tab",
                    "menu_links.content_id AS content_id",
                    "menu_links.collection_key AS collection_key",
                    "content_items.slug AS content_slug",
                    "content_items.content_type AS content_type"
                ])
                    .leftJoin("content_items", "menu_links.content_id", "=", "content_items.id")
                    .where("menu_links.location", location)
                    .where(visible -> {
                        visible.where(manual -> manual.where("menu_links.content_id", 0)
                            .where("menu_links.collection_key", ""))
                            .orWhere(content -> content.where("menu_links.content_id", ">", 0)
                                .where("content_items.status", "published")
                                .whereInQuery("content_items.content_type",
                                    ContentTypes.publicKeys()))
                            .orWhere(collection -> collection.where("menu_links.collection_key",
                                "!=", "")
                                .whereInQuery("menu_links.collection_key", archiveKeys));
                    })
                    .orderBy("menu_links.position")
                    .orderBy("menu_links.id")
                    .limit(region.max_links)
                    .get()
                    .map(model -> cast model.toObject());
            });
        return [
            for (row in records)
                {
                    id: row.id,
                    label: row.label,
                    url: row.content_id > 0 ? ContentTypes.url(row.content_type,
                        row.content_slug) : row.collection_key != "" ? ContentTypes.find(row.collection_key)
                        .publicBase : row.url,
                    new_tab: row.new_tab
                }
        ];
    }

    public static function forRegions(regions:Array<String>):Map<String, Array<NavigationLink>> {
        var result:Map<String, Array<NavigationLink>> = [];
        for (key in regions) {
            result.set(key, links(key));
        }
        return result;
    }
}
