package hx.press;

import hx.press.content.ContentTypes;
import hx.press.i18n.I18n;
import hx.well.http.Request;
import hx.well.route.Route;

typedef AdminNavigationLink = {
    var href:String;
    var label:String;
    var icon:String;
    var exact:Bool;
    var activePaths:Array<String>;
    var position:Int;
    @:optional var parent:String;
}

typedef AdminNavigationGroup = {
    var label:String;
    var links:Array<AdminNavigationLink>;
    var position:Int;
}

typedef AdminRouteNavigation = {
    var label:String;
    @:optional var group:String;
    @:optional var groupPosition:Int;
    @:optional var icon:String;
    @:optional var capability:String;
    @:optional var namespace:String;
    @:optional var position:Int;
    @:optional var exact:Bool;
    @:optional var anyCapabilities:Array<String>;
    @:optional var activePaths:Array<String>;
    @:optional var parent:String;
}

/** Navigation follows native route metadata and the current collection definitions. */
class AdminNavigation {
    /**
        The route attribute that makes a plugin's admin page its settings
        page, `{capability}`. The page stays out of the menu: the plugin's
        Settings button opens it, and Plugins is the current menu entry there.
    **/
    public static inline final SETTINGS = "cms.settings";

    /** The settings pages of active plugins, by plugin ID, that `permitted` capabilities may open. **/
    public static function settingsPages(permitted:String->Bool):Map<String, String> {
        var pages:Map<String, String> = [];
        for (route in Route.routes) {
            var plugin:String = route.getAttribute("hx.press.plugin", "");
            var entry:Dynamic = route.getAttribute(SETTINGS, null);
            if (plugin == ""
                || entry == null
                || pages.exists(plugin)
                || !route.getMethods().contains("GET")
                || !StringTools.startsWith(route.value, "/admin/")
                || route.value.indexOf("{") >= 0) {
                continue;
            }
            var capability:String = entry.capability is String ? entry.capability : "";
            if (capability == "" || permitted(capability)) {
                pages.set(plugin, route.value);
            }
        }
        return pages;
    }

    public static function groups(request:Request, pluginLinks:Array<Dynamic>,
            grants:Array<String>):Array<AdminNavigationGroup> {
        var groups:Map<String, AdminNavigationGroup> = [];
        var known:Map<String, Bool> = [];
        var allCapabilities = grants.contains("*");
        var contentAccess = CmsAccess.hasAccessibleCollections(grants);
        var permittedPages = settingsPages(capability -> allCapabilities
            || grants.contains(capability));
        var pluginSettings = [for (path in permittedPages) path];

        function append(group:String, groupPosition:Int, link:AdminNavigationLink):Void {
            if (known.exists(link.href)) {
                return;
            }
            known.set(link.href, true);
            var current = groups.get(group);
            if (current == null) {
                current = {label: I18n.t(group), position: groupPosition, links: []};
                groups.set(group, current);
            }
            current.links.push(link);
        }

        for (route in Route.routes) {
            var entry:AdminRouteNavigation = route.getAttribute("cms.navigation", null);
            if (entry == null
                || !route.getMethods().contains("GET")
                || !(route.value == "/admin" || StringTools.startsWith(route.value, "/admin/"))
                || route.value.indexOf("{") >= 0) {
                continue;
            }
            var capability:String = entry.capability ?? "";
            var permitted = capability == "content" ? contentAccess : capability == ""
                || allCapabilities || grants.contains(capability);
            var alternatives:Array<String> = entry.anyCapabilities ?? [];
            for (permission in alternatives) {
                permitted = permitted || allCapabilities || grants.contains(permission);
            }
            if (!permitted) {
                continue;
            }
            var link:AdminNavigationLink = {
                href: route.value,
                label: I18n.t(entry.label, null, entry.namespace ?? "cms"),
                icon: entry.icon ?? "file",
                exact: entry.exact == true,
                activePaths: entry.activePaths ?? [],
                position: entry.position ?? 50
            };
            if (route.value == "/admin/plugins") {
                link.activePaths = link.activePaths.concat(pluginSettings);
            }
            if (entry.parent != null) {
                link.parent = entry.parent;
            }
            append(entry.group ?? "Extensions", entry.groupPosition ?? 40, link);
        }
        if (contentAccess) {
            for (type in ContentTypes.navigation(request.route("kind") ?? "", grants)) {
                append("Content", 0, {
                    href: '/admin/${type.admin_path}',
                    label: I18n.t(type.name, null, type.owner == "" ? "cms" : type.owner),
                    icon: type.icon,
                    exact: false,
                    activePaths: [],
                    position: 10 + type.position
                });
            }
        }
        for (link in pluginLinks) {
            append("Extensions", 40, {
                href: link.href,
                label: link.label,
                icon: link.icon,
                exact: false,
                activePaths: [],
                position: 50
            });
        }
        var result = [for (group in groups) group];
        result.sort((left, right) -> left.position - right.position);
        for (group in result) {
            group.links.sort((left, right) -> {
                var position = left.position - right.position;
                return position == 0 ? Reflect.compare(left.label, right.label) : position;
            });
        }
        return result;
    }
}
