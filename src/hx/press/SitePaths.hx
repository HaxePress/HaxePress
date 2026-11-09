package hx.press;

/**
    Path prefixes that belong to no language: the administration, APIs,
    files and assets. They are never served under a language prefix, and
    links to them never get one.
**/
class SitePaths {
    static final prefixes = [
        "admin",
        "api",
        "mcp",
        "media",
        "storage",
        "build",
        "fonts",
        "images",
        "themes",
        "packages",
        "extension-assets",
        "theme-assets",
        "theme-design",
        "_wellout",
        "_translations",
        "categories",
        "locale",
        "favicon.ico",
        "robots.txt"
    ];

    /** The first segment of a site path, without its query or fragment. **/
    public static function firstSegment(path:String):String {
        var end = path.length;
        for (separator in ["/", "?", "#"]) {
            var index = path.indexOf(separator, 1);
            if (index >= 0 && index < end) {
                end = index;
            }
        }
        return path.substring(1, end);
    }

    /** Whether a site path stays the same in every language. **/
    public static function unlocalized(path:String):Bool {
        if (path == null || path.length < 2 || path.charAt(0) != "/") {
            return false;
        }
        return prefixes.contains(firstSegment(path));
    }

    /** The reserved segments, for pages that check paths in the browser. **/
    public static function list():Array<String> {
        return prefixes.copy();
    }
}
