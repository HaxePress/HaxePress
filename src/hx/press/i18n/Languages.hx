package hx.press.i18n;

import hx.press.ContentCache;
import hx.press.install.InstallationState;
import hx.press.model.Language;
import hx.well.facades.Environment;
import hx.well.http.RequestStatic;

typedef LanguageRecord = {
    var code:String;
    var name:String;
    var direction:String;
    var position:Int;
    var is_default:Int;
    var enabled:Int;
    var home_page_id:Int;
}

/** The languages of one database, read once per cache revision. **/
private class LanguageSet {
    public final revision:String;
    public final all:Array<LanguageRecord>;
    public final enabled:Array<LanguageRecord>;
    public final defaultCode:String;
    public final codes:Map<String, LanguageRecord>;
    public final segments:Map<String, LanguageRecord>;

    public function new(revision:String, all:Array<LanguageRecord>) {
        this.revision = revision;
        this.all = all;
        enabled = [for (language in all) if (language.enabled == 1) language];
        codes = [];
        segments = [];
        var first:Null<String> = null;
        var chosen:Null<String> = null;
        for (language in all) {
            codes.set(language.code, language);
            segments.set(Languages.segment(language.code), language);
            if (first == null) {
                first = language.code;
            }
            if (language.is_default == 1 && chosen == null) {
                chosen = language.code;
            }
        }
        defaultCode = chosen ?? first ?? I18n.FALLBACK;
    }
}

/**
    The languages the site publishes in. A site with one language has no
    language prefixes, switcher or alternates; every language feature asks
    `multilingual` or `publicMultilingual` first.

    The default language is served without a prefix and every other one
    under `/{segment}/`, where the segment is the lowercase code. Links in
    templates are written without a prefix, and the page's language is
    added when the page renders; `explicitPath` writes a link into another
    language.
**/
class Languages {
    /** The request attribute that holds the language of a public request. **/
    public static inline var ATTRIBUTE = "hx.press.language";

    public static inline var MAX_LANGUAGES = 32;

    static var known:Null<LanguageSet> = null;

    /** Native names of common languages, offered when a language is added. **/
    public static final names:Map<String, String> = [
        "ar" => "العربية",
        "bg" => "Български",
        "cs" => "Čeština",
        "da" => "Dansk",
        "de" => "Deutsch",
        "el" => "Ελληνικά",
        "en" => "English",
        "es" => "Español",
        "fa" => "فارسی",
        "fi" => "Suomi",
        "fr" => "Français",
        "he" => "עברית",
        "hi" => "हिन्दी",
        "hu" => "Magyar",
        "id" => "Bahasa Indonesia",
        "it" => "Italiano",
        "ja" => "日本語",
        "ko" => "한국어",
        "nl" => "Nederlands",
        "no" => "Norsk",
        "pl" => "Polski",
        "pt" => "Português",
        "ro" => "Română",
        "ru" => "Русский",
        "sv" => "Svenska",
        "th" => "ไทย",
        "tr" => "Türkçe",
        "uk" => "Українська",
        "vi" => "Tiếng Việt",
        "zh" => "中文"
    ];

    static final rightToLeft = ["ar", "fa", "he", "ur", "ps", "dv", "yi", "ku"];

    /**
        A language code: a two or three letter language, an optional script
        and an optional region, such as `en`, `pt-BR` or `zh-Hant-TW`.
    **/
    public static function validCode(code:String):Bool {
        if (code == null || code.length > 35) {
            return false;
        }
        var pattern = ~/^[a-z]{2,3}(?:-[A-Z][a-z]{3})?(?:-(?:[A-Z]{2}|[0-9]{3}))?(?![\s\S])/;
        return pattern.match(code);
    }

    /** The address segment of a language: its code in lowercase. **/
    public static function segment(code:String):String {
        return code.toLowerCase();
    }

    /** The native name of a known language, or the code. **/
    public static function suggestedName(code:String):String {
        var base = code.split("-")[0];
        return names.get(code) ?? names.get(base) ?? code;
    }

    /** The writing direction suggested for a language code. **/
    public static function suggestedDirection(code:String):String {
        return rightToLeft.contains(code.split("-")[0]) ? "rtl" : "ltr";
    }

    static function set():LanguageSet {
        if (InstallationState.pending) {
            var fallback = configuredDefault();
            return new LanguageSet("", [
                {
                    code: fallback,
                    name: suggestedName(fallback),
                    direction: suggestedDirection(fallback),
                    position: 0,
                    is_default: 1,
                    enabled: 1,
                    home_page_id: 0
                }
            ]);
        }
        var revision = ContentCache.revision("languages");
        var current = known;
        if (current != null && current.revision == revision) {
            return current;
        }
        var records:Array<LanguageRecord> = ContentCache.remember("languages", "list",
            [MAX_LANGUAGES], () -> {
                var rows = Language.query.select(["code", "name", "direction", "position", "is_default", "enabled", "home_page_id"])
                    .orderBy("position")
                    .orderBy("code")
                    .limit(MAX_LANGUAGES)
                    .get();
                return [for (row in rows) (cast row.toObject() : LanguageRecord)];
            });
        var loaded = new LanguageSet(revision, records);
        known = loaded;
        return loaded;
    }

    /** The language a new site starts with: `SITE_LANGUAGE`, or English. **/
    public static function configuredDefault():String {
        var configured = Environment.env("SITE_LANGUAGE", I18n.FALLBACK);
        return validCode(configured) ? configured : I18n.FALLBACK;
    }

    /** Every language in display order, including disabled ones. The list is shared. **/
    public static function all():Array<LanguageRecord> {
        return set().all;
    }

    /** The public languages in display order. The list is shared. **/
    public static function enabled():Array<LanguageRecord> {
        return set().enabled;
    }

    public static function codes():Array<String> {
        return [for (language in set().all) language.code];
    }

    public static function defaultCode():String {
        return set().defaultCode;
    }

    public static function find(code:String):Null<LanguageRecord> {
        return code == null ? null : set().codes.get(code);
    }

    public static function exists(code:String):Bool {
        return find(code) != null;
    }

    public static function isEnabled(code:String):Bool {
        var language = find(code);
        return language != null && language.enabled == 1;
    }

    /** Whether the site has more than one language, enabled or not: the administration offers translations. **/
    public static function multilingual():Bool {
        return set().all.length > 1;
    }

    /** Whether visitors can choose between languages. **/
    public static function publicMultilingual():Bool {
        return set().enabled.length > 1;
    }

    /** Whether any address can carry a language prefix. **/
    public static function prefixed():Bool {
        return set().all.length > 1;
    }

    public static function bySegment(segment:String):Null<LanguageRecord> {
        return set().segments.get(segment);
    }

    public static function name(code:String):String {
        var language = find(code);
        return language == null ? suggestedName(code) : language.name;
    }

    public static function direction(code:String):String {
        var language = find(code);
        return language == null ? suggestedDirection(code) : language.direction;
    }

    /** The language of the current public request, or the default language. **/
    public static function current():String {
        var request = RequestStatic.request();
        if (request != null) {
            var selected:Null<String> = request.getAttribute(ATTRIBUTE);
            if (selected != null && exists(selected)) {
                return selected;
            }
        }
        return defaultCode();
    }

    /** The address of `neutralPath` in a language: prefixed unless it is the default language. **/
    public static function path(code:String, neutralPath:String):String {
        if (code == defaultCode() || !exists(code)) {
            return neutralPath;
        }
        return prefix(code, neutralPath);
    }

    /**
        A link into a language that templates keep as written: the page's
        language is not added to it, and a default-language prefix is
        removed when the page renders.
    **/
    public static function explicitPath(code:String, neutralPath:String):String {
        return prefix(code, neutralPath);
    }

    static function prefix(code:String, neutralPath:String):String {
        var start = '/${segment(code)}';
        return neutralPath == "/" || neutralPath == "" ? start : start + neutralPath;
    }

    /** The language of a path's prefix, or null when it has none. **/
    public static function prefixOf(path:String):Null<LanguageRecord> {
        if (!prefixed() || path == null || path.length < 3 || path.charAt(0) != "/") {
            return null;
        }
        var end = path.indexOf("/", 1);
        var first = end < 0 ? path.substr(1) : path.substring(1, end);
        var candidate = first.indexOf("?") < 0 ? first : first.substr(0, first.indexOf("?"));
        return bySegment(candidate);
    }

    /** A path without its language prefix. **/
    public static function neutral(path:String):String {
        var language = prefixOf(path);
        if (language == null) {
            return path;
        }
        var rest = path.substr(segment(language.code).length + 1);
        if (rest == "") {
            return "/";
        }
        return rest.charAt(0) == "?" ? '/${rest}' : rest;
    }

    /** The `og:locale` form of a language code, such as `pt_BR`. **/
    public static function ogLocale(code:String):String {
        var parts = code.split("-");
        var language = parts[0];
        var region = parts.length > 1 ? parts[parts.length - 1] : "";
        return region.length == 2 ? '${language}_${region}' : language;
    }
}
