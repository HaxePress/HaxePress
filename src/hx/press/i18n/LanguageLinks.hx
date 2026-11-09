package hx.press.i18n;

import hx.press.SitePaths;

using StringTools;

/**
    Puts the page's language into the site links of a rendered page.
    Templates write links without a prefix, such as `/about`; on a German
    page the link becomes `/de/about`. A link that names a language with
    `Languages.explicitPath` keeps it, and a link into the default
    language loses its prefix.
**/
class LanguageLinks {
    /** The mapper for a page in `language`, or null when no link changes. **/
    public static function mapper(language:String):Null<String->String> {
        if (!Languages.prefixed()) {
            return null;
        }
        return href -> map(href, language);
    }

    public static function map(href:String, language:String):String {
        if (href == null || !href.startsWith("/") || href.startsWith("//")) {
            return href;
        }
        var named = Languages.prefixOf(href);
        if (named != null) {
            return named.code == Languages.defaultCode() ? Languages.neutral(href) : href;
        }
        if (SitePaths.unlocalized(href)) {
            return href;
        }
        return Languages.path(language, href);
    }
}
