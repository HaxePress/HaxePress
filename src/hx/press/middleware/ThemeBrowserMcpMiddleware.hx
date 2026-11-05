package hx.press.middleware;

import hx.press.CmsAccess;
import hx.press.model.ThemeDesign;
import hx.press.themes.ThemeAiAccess;
import hx.well.http.Request;
import hx.well.http.Response;
import hx.well.http.ResponseBuilder;
import hx.well.middleware.AbstractMiddleware;

/** Browser sockets require the existing admin guard and an explicit trusted Origin. */
class ThemeBrowserMcpMiddleware extends AbstractMiddleware {
    public function handle(request:Request, next:Request->Null<Response>):Null<Response> {
        var origin = request.header("Origin", "");
        if (origin == "" || !ThemeAiAccess.allowedOrigin(origin)) {
            return ResponseBuilder.asJson({error: "This browser origin is not allowed."}, 403);
        }
        if (!CmsAccess.can("extensions")) {
            return ResponseBuilder.asJson({error: "Theme management access is required."}, 403);
        }
        if (!ThemeDesign.query.where("id", request.route("id")).exists()) {
            return ResponseBuilder.asJson({error: "This theme is no longer available."}, 404);
        }
        return next(request);
    }
}
