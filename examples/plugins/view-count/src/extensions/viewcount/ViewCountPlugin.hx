package extensions.viewcount;

import haxe.Json;
import hx.press.access.Roles;
import hx.press.i18n.I18n;
import hx.press.plugins.PluginEntrypoint;
import hx.press.plugins.PluginHost;
import hx.well.route.Route;
import hx.well.route.RouteElement;

/**
    Counts visitors' views of published content. The application decides
    which requests are views and hands them over once a minute with the
    `content.viewed` hook; this plugin adds them to one row per content
    item and, when its country setting is on, to one row per content item
    and country. Countries come from the Cloudflare plugin; without a
    trusted country a view counts as `UNKNOWN`.

    Its page lists the most viewed content, `/countries` lists the views by
    country, `/data` and `/countries/data` answer the same as JSON and as
    MCP tools, the dashboard shows the total, and content pages can show
    their count through `site.shared`.
**/
class ViewCountPlugin implements PluginEntrypoint {
    public static inline var NAMESPACE = "plugin-view-count";
    public static inline var CAPABILITY = "view_counts";
    public static inline var PAGE = "/admin/view-counts";
    public static inline var COUNTRY_PAGE = "/admin/view-counts/countries";
    public static inline var SETTINGS_PAGE = "/admin/plugins/plugin-view-count/settings";

    /** Whether the plugin's setting asks to count views by country as well. **/
    public static var countingCountries = false;

    var routes:Array<RouteElement> = [];
    var host:PluginHost;

    public function new() {}

    public function onCreate(host:PluginHost, context:String):Void {
        this.host = host;
        configure(Json.parse(context));
        ViewCounts.migrate();
        Roles.ensureCapability(CAPABILITY, "See content view counts", "Statistics", NAMESPACE);
        host.admin(() -> {
            routes.push(Route.get("/view-counts", new ViewCountsPage(host))
                .attribute("cms.navigation", {
                    label: "View counts",
                    namespace: NAMESPACE,
                    icon: "eye",
                    capability: CAPABILITY,
                    exact: true
                }));
            routes.push(Route.get("/view-counts/data", new ViewCountsData(host))
                .attribute("cms.mcp", {
                    name: "views",
                    description: "List published content by counted views, most viewed first, or read the views of one content item. Counts are updated once a minute.",
                    capability: CAPABILITY,
                    inputSchema: {
                        type: "object",
                        properties: {
                            content: {type: "integer", minimum: 1, maximum: 2147483647},
                            cursor: {type: "string", maxLength: 512},
                            limit: {type: "integer", minimum: 1, maximum: ViewCounts.MAX_LIMIT}
                        }
                    }
                }));
            routes.push(Route.get("/view-counts/countries", new CountryViewsPage(host))
                .attribute("cms.navigation", {
                    label: "Views by country",
                    namespace: NAMESPACE,
                    icon: "compass",
                    capability: CAPABILITY,
                    parent: PAGE
                }));
            routes.push(Route.get("/view-counts/countries/data", new CountryViewsData(host))
                .attribute("cms.mcp", {
                    name: "country_views",
                    description: "List counted views of published content per content item and visitor country, most views first, while the plugin counts countries. Filter by a content ID or a country code; UNKNOWN collects views without a country from the Cloudflare plugin. Counts are updated once a minute.",
                    capability: CAPABILITY,
                    inputSchema: {
                        type: "object",
                        properties: {
                            content: {type: "integer", minimum: 1, maximum: 2147483647},
                            country: {type: "string", pattern: "^(?:[A-Z]{2}|UNKNOWN)$"},
                            cursor: {type: "string", maxLength: 512},
                            limit: {type: "integer", minimum: 1, maximum: CountryViewData.MAX_LIMIT}
                        }
                    }
                }));
        });
    }

    public function onDestroy():Void {
        for (route in routes) {
            Route.unregister(route);
        }
        routes = [];
    }

    public function dispatch(event:String, context:String):String {
        var input:Dynamic = Json.parse(context);
        if (event == "content.viewed") {
            var views:Array<Dynamic> = input.data.views;
            ViewCounts.add(views);
            if (countries(input)) {
                CountryViewData.add(views);
            }
            return "{}";
        }
        if (event == "settings.saved") {
            configure(input);
            return "{}";
        }
        if (event == "site.shared") {
            return Json.stringify(contentBlock(input));
        }
        if (event == "dashboard.widgets" && host.can(CAPABILITY)) {
            return Json.stringify(dashboard());
        }
        return "{}";
    }

    static function countries(input:Dynamic):Bool {
        var settings:Dynamic = input.settings;
        return settings != null && settings.count_countries == "true";
    }

    static function configure(input:Dynamic):Void {
        countingCountries = countries(input);
    }

    /** The count of the content item a public page shows, when the settings ask for it. **/
    static function contentBlock(input:Dynamic):Dynamic {
        var content:Dynamic = input.data.content;
        var settings:Dynamic = input.settings;
        if (content == null || settings.show_count != "true") {
            return {};
        }
        var id:Int = content.id;
        var views = 0;
        try {
            views = ViewCounts.forContent(id);
        } catch (error:Dynamic) {
            // The page renders without its count rather than turn the plugin off.
            return {};
        }
        if (views == 0) {
            return {};
        }
        var slot:String = settings.position == "content.before" ? "content.before" : "content.after";
        var text = I18n.t("{views} views",
            ["count" => views, "views" => ViewCounts.format(views)], NAMESPACE);
        return {blocks: [{slot: slot, content: text}]};
    }

    static function dashboard():Dynamic {
        var heading = I18n.t("View counts", null, NAMESPACE);
        var total = ViewCounts.format(ViewCounts.total());
        var summary = I18n.t("{views} views in total. [See the most viewed content]({page}).",
            ["views" => total, "page" => PAGE], NAMESPACE);
        return {blocks: [{slot: "dashboard", content: '### ${heading}\n\n${summary}'}]};
    }
}
