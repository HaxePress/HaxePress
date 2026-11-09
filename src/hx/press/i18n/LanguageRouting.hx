package hx.press.i18n;

import hx.press.SitePaths;
import hx.press.install.InstallationState;
import hx.well.http.Request;

/**
    Serves every public route under the prefix of each site language. It
    runs before routes are resolved: `/de/blog/hello` is resolved as
    `/blog/hello` in German, so core and plugin routes need no second
    registration. The default language has no prefix, and its prefix
    redirects to the address without it.
**/
class LanguageRouting {
    /** Set to the address without the prefix when the default language's prefix is used. **/
    public static inline var DEFAULT_PREFIX = "hx.press.language.defaultPrefix";

    /** Set to a disabled language whose address was requested. **/
    public static inline var DISABLED = "hx.press.language.disabled";

    public static function rewrite(request:Request):Void {
        if (InstallationState.pending) {
            return;
        }
        var path = request.path;
        if (path == null || path.length < 3 || path.charAt(0) != "/") {
            return;
        }
        var first = SitePaths.firstSegment(path);
        // Most paths cannot be a language code, which saves reading the languages.
        var shape = ~/^[a-z]{2,3}(?:-[a-z0-9]{2,8})*(?![\s\S])/;
        if (!shape.match(first) || !Languages.prefixed()) {
            return;
        }
        var language = Languages.bySegment(first);
        if (language == null) {
            return;
        }
        var rest = path.substr(first.length + 1);
        if (rest == "") {
            rest = "/";
        }
        if (SitePaths.unlocalized(rest)) {
            return;
        }
        if (language.code == Languages.defaultCode()) {
            request.setAttribute(DEFAULT_PREFIX, rest);
            return;
        }
        // Setting the path parses its query again; this path has none, so the request keeps its own.
        var queries = request.queries;
        request.path = rest;
        request.queries = queries;
        if (language.enabled != 1) {
            request.setAttribute(DISABLED, language.code);
            return;
        }
        request.setAttribute(Languages.ATTRIBUTE, language.code);
    }
}
