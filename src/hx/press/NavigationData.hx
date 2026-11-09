package hx.press;

import hx.press.i18n.SiteTexts;
import hx.press.i18n.Languages;
import hx.press.model.ContentItem;
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
    var content_language:Null<String>;
    var content_group:Null<String>;
}

class NavigationData {
    public static inline var MAX_LINKS = 12;

    public static function ensure():Void {
        if (Setting.query.where("key", "cms_navigation_v1").exists()) {
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
                    var seededId = MenuLink.query.insert([
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
                    SiteTexts.put('menu.${seededId}.label', "menu", link.label);
                }
            }
            Setting.query.insert(["key" => "cms_navigation_v1", "value" => "1"]);
        });
        ContentCache.changed("navigation");
    }

    public static function links(location:String):Array<NavigationLink> {
        var region = NavigationRegions.find(location);
        if (region == null || region.enabled != 1) {
            return [];
        }
        var contentRevision = ContentCache.revision("items");
        var language = Languages.current();
        var multilingual = Languages.prefixed();
        var records:Array<NavigationSource> = ContentCache.remember("navigation", "location",
            [location, region.max_links, contentRevision, ContentTypes.revision(), language],
            () -> {
                var archiveKeys = ContentTypes.publicKeys().where("has_archive", 1);
                var rows:Array<NavigationSource> = MenuLink.query.select([
                    "menu_links.id AS id",
                    "menu_links.label AS label",
                    "menu_links.url AS url",
                    "menu_links.new_tab AS new_tab",
                    "menu_links.content_id AS content_id",
                    "menu_links.collection_key AS collection_key",
                    "content_items.slug AS content_slug",
                    "content_items.content_type AS content_type",
                    "content_items.language AS content_language",
                    "content_items.translation_group AS content_group"
                ])
                    .leftJoin("content_items", "menu_links.content_id", "=", "content_items.id")
                    .where("menu_links.location", location)
                    .where(shown -> shown.where("menu_links.language", "")
                        .orWhere("menu_links.language", language))
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
                return multilingual ? translated(rows, language) : rows;
            });
        var labels = SiteTexts.texts([for (row in records) 'menu.${row.id}.label']);
        return [
            for (row in records)
                {
                    id: row.id,
                    label: labels.get('menu.${row.id}.label') ?? row.label,
                    url: row.content_id > 0 ? contentUrl(row,
                        language) : row.collection_key != "" ? ContentTypes.find(row.collection_key)
                        .publicBase : row.url,
                    new_tab: row.new_tab
                }
        ];
    }

    /** A link to content leads to its translation in the page's language when it has one. **/
    static function translated(rows:Array<NavigationSource>,
            language:String):Array<NavigationSource> {
        var groups = [
            for (row in rows)
                if (row.content_id > 0 && row.content_language != language
                    && row.content_group != null && row.content_group != "") row.content_group
        ];
        if (groups.length == 0) {
            return rows;
        }
        var found:Map<String, String> = [];
        var translations = ContentItem.query.select(["translation_group", "slug"])
            .where(listed -> listed.whereIn("translation_group", cast groups))
            .where("language", language)
            .where("status", "published")
            .limit(groups.length)
            .get();
        for (translation in translations) {
            found.set(translation.translation_group, translation.slug);
        }
        for (row in rows) {
            var slug = row.content_group == null ? null : found.get(row.content_group);
            if (slug != null) {
                row.content_slug = slug;
                row.content_language = language;
            }
        }
        return rows;
    }

    /**
        The address of a linked item. An item of another language keeps its
        language's prefix, which a page's links do not change.
    **/
    static function contentUrl(row:NavigationSource, language:String):String {
        var path = ContentTypes.url(row.content_type, row.content_slug);
        var own = row.content_language;
        if (path == null || own == null || own == "" || own == language || !Languages.prefixed()) {
            return path;
        }
        return Languages.explicitPath(own, path);
    }

    public static function forRegions(regions:Array<String>):Map<String, Array<NavigationLink>> {
        var result:Map<String, Array<NavigationLink>> = [];
        for (key in regions) {
            result.set(key, links(key));
        }
        return result;
    }
}
