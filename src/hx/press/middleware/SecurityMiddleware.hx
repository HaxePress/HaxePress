package hx.press.middleware;

import hx.well.middleware.AbstractMiddleware;
import hx.well.http.Request;
import hx.well.http.Response;
import hx.well.http.ResponseStatic;
import hx.well.route.RouteElement;
import hx.well.type.AttributeType;

class SecurityMiddleware extends AbstractMiddleware {
    public function handle(request:Request, next:Request->Null<Response>):Null<Response> {
        var route:RouteElement = request.getAttribute(AttributeType.RouteElement);
        var previewFrame = route != null && route.getAttribute("theme.preview.frame", false);
        var framePolicy = previewFrame ? "SAMEORIGIN" : "DENY";
        ResponseStatic.get()
            .header("X-Content-Type-Options", "nosniff")
            .header("X-Frame-Options", framePolicy)
            .header("Referrer-Policy", "strict-origin-when-cross-origin");
        if (previewFrame) {
            ResponseStatic.get().header("Content-Security-Policy", "frame-ancestors 'self'");
        }
        if (request.path == "/admin" || StringTools.startsWith(request.path, "/admin/"))
            ResponseStatic.get().header("Cache-Control", "no-store");
        return next(request);
    }
}
