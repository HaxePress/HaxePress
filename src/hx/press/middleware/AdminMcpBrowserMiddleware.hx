package hx.press.middleware;

import hx.press.themes.ThemeAiAccess;
import hx.well.http.Request;
import hx.well.http.Response;
import hx.well.http.ResponseBuilder;
import hx.well.middleware.AbstractMiddleware;

class AdminMcpBrowserMiddleware extends AbstractMiddleware {
    public function handle(request:Request, next:Request->Null<Response>):Null<Response> {
        var origin = request.header("Origin", "");
        if (origin == "" || !ThemeAiAccess.allowedOrigin(origin)) {
            return ResponseBuilder.asJson({error: "This browser origin is not allowed."}, 403);
        }
        return next(request);
    }
}
