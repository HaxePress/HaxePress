package hx.press.i18n;

import hx.press.content.ContentTranslations;
import hx.press.view.ViewRoots;
import hx.well.facades.Environment;
import hx.well.http.Request;

/**
    The `seo` root of public pages: the canonical address and, on a site
    with several public languages, the address of the page in each of them
    (`hreflang`). Content pages link their published translations; pages
    that show the same thing in every language, such as the homepage, link
    every language; filtered and paged lists link none.
**/
class PageSeo {
    /** Set by content pages to the item they show: `{canonical, group, kind, paths}`. **/
    public static inline var CONTENT = "hx.press.seo.content";

    public static function forRequest(request:Null<Request>):Dynamic {
        if (request == null || ViewRoots.isAdmin(request)) {
            return null;
        }
        var base = StringTools.replace(Environment.env("APP_URL", ""), "\n", "");
        if (StringTools.endsWith(base, "/")) {
            base = base.substr(0, base.length - 1);
        }
        var current = Languages.current();
        var content:Dynamic = request.getAttribute(CONTENT, null);
        var canonical = content != null ? Std.string(content.canonical) : Languages.path(current,
            request.path);
        var alternates:Array<Dynamic> = [];
        var listed = request.queries.keys().hasNext();
        if (Languages.publicMultilingual() && !(content == null && listed)) {
            var paths:Map<String, String> = [];
            if (content != null) {
                var group:String = content.group;
                var kind:String = content.kind;
                var publicBase:String = content.publicBase;
                for (entry in ContentTranslations.published(group, kind)) {
                    if (Languages.isEnabled(entry.language)) {
                        paths.set(entry.language,
                            Languages.path(entry.language,
                                '${publicBase}/${StringTools.urlEncode(entry.slug)}'));
                    }
                }
            } else {
                for (language in Languages.enabled()) {
                    paths.set(language.code, Languages.path(language.code, request.path));
                }
            }
            var codes = [for (code in paths.keys()) code];
            if (codes.length > 1) {
                codes.sort(Reflect.compare);
                for (code in codes) {
                    alternates.push({language: code, href: '${base}${paths.get(code)}'});
                }
                var fallback = paths.get(Languages.defaultCode());
                if (fallback != null) {
                    alternates.push({language: "x-default", href: '${base}${fallback}'});
                }
            }
        }
        var ogAlternates = [
            for (alternate in alternates)
                if (alternate.language != "x-default" && alternate.language != current)
                    Languages.ogLocale(alternate.language)
        ];
        return {
            canonical: '${base}${canonical}',
            alternates: alternates,
            ogLocale: Languages.ogLocale(current),
            ogAlternates: ogAlternates
        };
    }
}
