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
import hx.press.content.ContentViews;
import hx.well.http.RequestStatic.auth;

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
        markMember(request, secure, cookie.maxAge);
        // HxWell disposes middleware after sending the response. Persist the admin
        // session before returning so an immediate redirect cannot outrun its write.
        if (!request.session.save()) {
            request.session.touch();
        }
        request.session.needsRefresh = false;
    }

    /**
        Public pages run without this session, so plugins that count visits
        recognize a signed-in member's browser by `ContentViews.MEMBER_COOKIE`
        on the whole site. It grants nothing, so it needs no protection.
    **/
    function markMember(request:Request, secure:Bool, maxAge:Null<Int>):Void {
        var signedIn = auth("admin").check();
        if (!signedIn && request.cookie(ContentViews.MEMBER_COOKIE) == null) {
            return;
        }
        var member = new CookieData(ContentViews.MEMBER_COOKIE, "1");
        member.path = "/";
        member.secure = secure;
        member.maxAge = signedIn ? maxAge : 0;
        ResponseStatic.get().cookieFromData(member.key, member);
    }
}
