package hx.press.middleware;

import hx.well.middleware.AbstractMiddleware;
import hx.well.middleware.SessionMiddleware;
import hx.well.middleware.CsrfMiddleware;
import hx.well.http.Request;
import hx.well.http.Response;
import hx.well.http.ResponseStatic;
import hx.well.http.CookieData;
import hx.well.facades.Config;
import hx.well.facades.Environment;
import hx.press.ai.AdminMcpAccess;

/** Cookie policy for the /admin group. Public routes never run this middleware. */
class AdminSessionMiddleware extends AbstractMiddleware {
    public function handle(request:Request, next:Request->Null<Response>):Null<Response> {
        if (request.getAttribute(AdminMcpAccess.INTERNAL, false)) {
            return next(request);
        }
        try {
            var result = next(request);
            apply(request);
            return result;
        } catch (error:Dynamic) {
            apply(request);
            throw error;
        }
    }

    function apply(request:Request):Void {
        var secure = Environment.env("APP_ENV") != "development";
        var cookie = new CookieData(SessionMiddleware.sessionCookieKey(),
            request.session.sessionKey, true);
        cookie.path = "/admin";
        cookie.secure = secure;
        cookie.maxAge = Config.get("session.lifetime") * 60;
        ResponseStatic.get().cookieFromData(cookie.key, cookie);
        request.session.needsRefresh = true;
        var token:String = request.session.get(CsrfMiddleware.TOKEN_KEY);
        if (token != null) {
            var xsrf = new CookieData("XSRF-TOKEN", token);
            xsrf.path = "/admin";
            xsrf.secure = secure;
            xsrf.httpOnly = false;
            ResponseStatic.get().cookieFromData(xsrf.key, xsrf);
        }
        // HxWell disposes middleware after sending the response. Persist the admin
        // session before returning so an immediate redirect cannot outrun its write.
        if (!request.session.save()) {
            request.session.touch();
        }
        request.session.needsRefresh = false;
    }
}
