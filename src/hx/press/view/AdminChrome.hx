package hx.press.view;

import hx.well.http.Request;

/**
    The admin sidebar and breadcrumb for the current page, prepared from
    the admin navigation like the former AdminLayout component did in the
    browser.
**/
class AdminChrome {
    static function isCurrent(link:Dynamic, path:String):Bool {
        var aliases:Null<Array<String>> = link.activePaths;
        if (aliases != null) {
            for (prefix in aliases) {
                if (path == prefix || StringTools.startsWith(path, '${prefix}/')) {
                    return true;
                }
            }
        }
        var href:String = link.href;
        return link.exact == true ? path == href : path == href
            || StringTools.startsWith(path, '${href}/');
    }

    public static function sidebar(groups:Array<Dynamic>, request:Null<Request>):Array<Dynamic> {
        var path = request == null ? "/admin" : request.path;
        var result:Array<Dynamic> = [];
        for (group in groups) {
            var links:Array<Dynamic> = group.links;
            if (links == null || links.length == 0) {
                continue;
            }
            var hrefs = [for (link in links) Std.string(link.href)];
            result.push({
                label: group.label,
                links: [
                    for (link in links)
                        {
                            href: link.href,
                            label: link.label,
                            icon: link.icon,
                            current: isCurrent(link, path),
                            child: link.parent != null && hrefs.indexOf(link.parent) >= 0}
                ]
            });
        }
        return result;
    }

    public static function location(groups:Array<Dynamic>, request:Null<Request>,
            host:ViewHost):Dynamic {
        var path = request == null ? "/admin" : request.path;
        var bestGroup:Dynamic = null;
        var bestLink:Dynamic = null;
        for (group in groups) {
            var links:Array<Dynamic> = group.links;
            for (link in links) {
                if (!isCurrent(link, path)) {
                    continue;
                }
                var href:String = link.href;
                if (bestLink == null || href.length > Std.string(bestLink.href).length) {
                    bestGroup = group;
                    bestLink = link;
                }
            }
        }
        var location:Dynamic = {
            group: bestGroup == null ? host.t("Administration", null) : bestGroup.label,
            current: bestLink == null ? host.t("Overview", null) : bestLink.label
        };
        if (bestLink != null && bestLink.parent != null) {
            var links:Array<Dynamic> = bestGroup.links;
            for (link in links) {
                if (link.href == bestLink.parent) {
                    location.parentHref = link.href;
                    location.parentLabel = link.label;
                }
            }
        }
        return location;
    }

    public static function initials(name:String):String {
        var parts = [for (part in ~/\s+/g.split(StringTools.trim(name))) if (part != "") part];
        var letters = [for (part in parts.slice(0, 2)) part.charAt(0)];
        return letters.join("");
    }
}
