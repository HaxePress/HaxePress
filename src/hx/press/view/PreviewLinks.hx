package hx.press.view;

import hx.press.i18n.I18n;
import hx.well.http.Request;

/**
    Keeps links inside a theme preview: public page paths get the preview
    base, the selected language and the customization session, like the
    former `previewHref` in the browser. While the customizer has unsaved
    values, links also keep them, so the frame shows the draft on every page.
**/
class PreviewLinks {
    static final reserved = [
        "admin",
        "api",
        "media",
        "storage",
        "build",
        "fonts",
        "images",
        "themes",
        "packages",
        "extension-assets",
        "locale"
    ];

    public static function mapper(theme:Dynamic, request:Null<Request>):Null<String->String> {
        if (theme == null) {
            return null;
        }
        var base:Null<String> = theme.previewBase;
        if (base == null || base == "") {
            return null;
        }
        var session:Null<String> = theme.customizeSession;
        var locale = I18n.locale();
        var draft = session == null || request == null ? "" : request.query("preview_settings", "");
        return url -> map(url, base, locale, session, draft);
    }

    public static function map(href:String, base:String, locale:Null<String>,
            session:Null<String>, draft:String = ""):String {
        if (!StringTools.startsWith(href, "/") || StringTools.startsWith(href, "//")) {
            return href;
        }
        var hash = "";
        var hashIndex = href.indexOf("#");
        var withoutHash = href;
        if (hashIndex >= 0) {
            hash = href.substr(hashIndex);
            withoutHash = href.substr(0, hashIndex);
        }
        var queryIndex = withoutHash.indexOf("?");
        var path = queryIndex < 0 ? withoutHash : withoutHash.substr(0, queryIndex);
        var search = queryIndex < 0 ? "" : withoutHash.substr(queryIndex + 1);
        var first = path.split("/")[1];
        var publicPath = ~/^\/[a-z0-9-]+(?:\/[a-z0-9-]+)?$/;
        var isPublic = path == "/" || (publicPath.match(path) && reserved.indexOf(first) < 0);
        if (!isPublic) {
            return href;
        }
        var pairs = search == "" ? [] : [
            for (pair in search.split("&"))
                if (!StringTools.startsWith(pair, "lang=")
                    && !StringTools.startsWith(pair, "customizeSession=")
                    && !StringTools.startsWith(pair, "preview_settings=")) pair
        ];
        if (locale != null && locale != "") {
            pairs.push('lang=${StringTools.urlEncode(locale)}');
        }
        if (session != null && session != "") {
            pairs.push('customizeSession=${StringTools.urlEncode(session)}');
            if (draft != "") {
                pairs.push('preview_settings=${StringTools.urlEncode(draft)}');
            }
        }
        var pathname = path == "/" ? "" : path;
        var query = pairs.length == 0 ? "" : '?${pairs.join("&")}';
        return '${base}${pathname}${query}${hash}';
    }
}
