package hx.press.middleware;

import hx.press.install.InstallationState;
import hx.press.i18n.I18n;
import hx.well.http.Request;
import hx.well.http.Response;
import hx.well.middleware.AbstractMiddleware;

class LocaleMiddleware extends AbstractMiddleware {
    public function handle(request:Request, next:Request->Null<Response>):Null<Response> {
        if (InstallationState.pending) {
            request.setAttribute("hx.press.locale", "en");
            return next(request);
        }
        var selected = request.query("lang", request.cookie("cms_locale", ""));
        if (!I18n.supported(selected)) {
            selected = I18n.defaultLocale();
        }
        request.setAttribute("hx.press.locale", selected);
        var response = next(request);
        if (response != null) {
            response.header("Content-Language", selected);
            response.header("Vary", "Cookie, X-Inertia");
        }
        return response;
    }
}
