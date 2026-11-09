package hx.press.middleware;

import hx.press.i18n.I18n;
import hx.well.middleware.AbstractMiddleware;
import hx.well.http.Request;
import hx.well.http.Response;
import hx.well.http.ResponseBuilder;
import hx.press.CmsAccess;

class AdminMiddleware extends AbstractMiddleware {
    public function handle(request:Request, next:Request->Null<Response>):Null<Response> {
        var admin = CmsAccess.current();
        if (admin == null) {
            return ResponseBuilder.asRedirect("/admin/login", 303);
        }
        var preview = request.getAttribute(LocaleMiddleware.PREVIEW, false);
        if (!preview && I18n.adminLocale(admin.ui_language)) {
            request.setAttribute("hx.press.locale", admin.ui_language);
        }
        return next(request);
    }
}
