package hx.press.middleware;

import hx.press.themes.ThemeAiAccess;
import hx.well.http.Request;
import hx.well.http.Response;
import hx.well.http.ResponseBuilder;
import hx.well.middleware.AbstractMiddleware;

/** Scoped MCP credentials are separate from browser sessions and never authorize admin routes. */
class ThemeAiMiddleware extends AbstractMiddleware {
    public function handle(request:Request, next:Request->Null<Response>):Null<Response> {
        var actor = ThemeAiAccess.authenticate(request);
        if (actor == null) {
            return
                ResponseBuilder.asJson({error: "This AI connection is invalid, expired or revoked."},
                    401)
                .header("WWW-Authenticate", 'Bearer realm="theme-designer"')
                .header("Cache-Control", "private, no-store");
        }
        if (!actor.permissions.read || (request.method == "POST" && !actor.permissions.edit)) {
            return
                ResponseBuilder.asJson({error: "This AI connection does not have permission for this operation."},
                    403);
        }
        request.setAttribute(ThemeAiAccess.ACTOR, actor);
        var response = next(request);
        if (response != null) {
            response.header("Cache-Control", "private, no-store");
        }
        return response;
    }
}
