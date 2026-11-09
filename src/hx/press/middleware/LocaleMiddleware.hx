package hx.press.middleware;

import hx.press.install.InstallationState;
import hx.press.i18n.I18n;
import hx.press.i18n.LanguageRedirects;
import hx.press.i18n.LanguageRouting;
import hx.press.i18n.Languages;
import hx.well.http.ResponseBuilder;
import hx.press.handler.admin.account.ChangeAdminLocaleHandler;
import hx.well.type.AttributeType;
import hx.well.http.Request;
import hx.well.http.Response;
import hx.well.middleware.AbstractMiddleware;
import hx.well.route.RouteElement;

using StringTools;

/**
    Chooses the language a request renders in. Public pages use the site's
    language. The administration uses each member's own interface language,
    which `AdminMiddleware` applies after signing in; before that the
    `cms_locale` cookie or the browser's languages choose it.
**/
class LocaleMiddleware extends AbstractMiddleware {
    /** Set on theme preview frames, which keep the site's language after signing in. **/
    public static inline var PREVIEW = "hx.press.preview.locale";

    public function handle(request:Request, next:Request->Null<Response>):Null<Response> {
        if (InstallationState.pending) {
            request.setAttribute("hx.press.locale", "en");
            return next(request);
        }
        var path = request.path;
        var administration = path == "/admin" || path.startsWith("/admin/");
        if (!administration) {
            var redirect = languageRedirect(request);
            if (redirect != null) {
                return redirect;
            }
        }
        var selected = administration ? adminLocale(request) : publicLocale(request);
        request.setAttribute("hx.press.locale", selected);
        var response = next(request);
        if (response != null) {
            // Signing in or a preview may choose another language after this middleware.
            response.header("Content-Language", I18n.locale());
            // Replaces the Vary of the page, so it keeps the headers pages vary on: fragment
            // requests and page data for tests and the site's MCP tools.
            response.header("Vary", "Cookie, Well-Fragment, X-Well-Data");
        }
        return response;
    }

    /** Public pages are in the language of their address. **/
    static function publicLocale(request:Request):String {
        return Languages.current();
    }

    /**
        The default language's prefix moves permanently to the address
        without it. A disabled language's address goes to the same content
        in the default language, or the homepage, while it stays disabled.
    **/
    static function languageRedirect(request:Request):Null<Response> {
        var method = request.method == null ? "GET" : request.method.toUpperCase();
        var reading = method == "GET" || method == "HEAD";
        var unprefixed:Null<String> = request.getAttribute(LanguageRouting.DEFAULT_PREFIX, null);
        if (unprefixed != null) {
            return reading ? ResponseBuilder.asRedirect(withQuery(unprefixed, request), 301) : null;
        }
        var disabled:Null<String> = request.getAttribute(LanguageRouting.DISABLED, null);
        if (disabled != null) {
            return ResponseBuilder.asRedirect(LanguageRedirects.disabled(request.path, disabled),
                302);
        }
        return null;
    }

    static function withQuery(path:String, request:Request):String {
        var pairs:Array<String> = [];
        for (key => value in request.queries) {
            pairs.push('${StringTools.urlEncode(key)}=${StringTools.urlEncode(value)}');
        }
        return pairs.length == 0 ? path : '${path}?${pairs.join("&")}';
    }

    static function adminLocale(request:Request):String {
        var route:Null<RouteElement> = request.getAttribute(AttributeType.RouteElement);
        if (route != null && route.getAttribute("theme.preview.frame", false)) {
            // A preview frame renders the public site, in the language it previews.
            request.setAttribute(PREVIEW, true);
            var previewed = request.query("lang", "");
            if (!Languages.exists(previewed)) {
                previewed = Languages.defaultCode();
            }
            request.setAttribute(Languages.ATTRIBUTE, previewed);
            return previewed;
        }
        var chosen = request.cookie(ChangeAdminLocaleHandler.COOKIE, "");
        if (I18n.adminLocale(chosen)) {
            return chosen;
        }
        return I18n.preferredAdminLocale(request.header("Accept-Language"));
    }
}
