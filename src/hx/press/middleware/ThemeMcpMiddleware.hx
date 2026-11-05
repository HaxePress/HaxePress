package hx.press.middleware;

import hx.press.themes.ThemeAiAccess;
import hx.well.http.Request;
import hx.well.http.Response;
import hx.well.http.ResponseBuilder;
import hx.well.middleware.AbstractMiddleware;

class ThemeMcpMiddleware extends AbstractMiddleware {
    public function handle(request:Request, next:Request->Null<Response>):Null<Response> {
        if (!ThemeAiAccess.allowedOrigin(request.header("Origin", ""))) {
            return ResponseBuilder.asJson({error: "This MCP origin is not allowed."}, 403);
        }
        var actor = ThemeAiAccess.authenticateToken(request.route("id"),
            request.header("Authorization", ""));
        if (actor == null) {
            return
                ResponseBuilder.asJson({error: "This AI connection is invalid, expired or revoked."},
                    401)
                .header("WWW-Authenticate", 'Bearer realm="theme-designer"')
                .header("Cache-Control", "private, no-store");
        }
        request.setAttribute(ThemeAiAccess.ACTOR, actor);
        return next(request);
    }
}
