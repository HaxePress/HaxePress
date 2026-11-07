package hx.press.middleware;

import hx.press.view.View;
import hx.well.middleware.AbstractMiddleware;
import hx.well.http.Request;
import hx.well.http.Response;
import hx.well.http.ResponseStatic;
import hx.well.route.RouteElement;
import hx.well.type.AttributeType;

class SecurityMiddleware extends AbstractMiddleware {
    /**
        The Content Security Policy of a response. Scripts run only from this
        site or with this request's nonce, which the renderer puts on its own
        scripts, so injected markup cannot run script. Styles stay open to
        inline values, which themes use for their settings.
    **/
    static function policy(nonce:String, framed:Bool, host:Null<String>):String {
        var plainHost = ~/^(?:[A-Za-z0-9.-]+|\[[0-9A-Fa-f:.]+\])(?::[0-9]{1,5})?$/;
        var sockets = host != null && plainHost.match(host) ? ' ws://${host} wss://${host}' : "";
        var ancestors = framed ? "'self'" : "'none'";
        var directives = [
            "default-src 'self'",
            'script-src \'self\' \'nonce-${nonce}\'',
            "style-src 'self' 'unsafe-inline'",
            "img-src 'self' data: blob: https:",
            "font-src 'self' data:",
            'connect-src \'self\'${sockets}',
            "object-src 'none'",
            "base-uri 'none'",
            "form-action 'self'",
            'frame-ancestors ${ancestors}'
        ];
        return directives.join("; ");
    }

    public function handle(request:Request, next:Request->Null<Response>):Null<Response> {
        var route:RouteElement = request.getAttribute(AttributeType.RouteElement);
        var contentPreview = route != null && route.getAttribute("content.preview", false);
        var previewFrame = contentPreview
            || (route != null && route.getAttribute("theme.preview.frame", false));
        var framePolicy = previewFrame ? "SAMEORIGIN" : "DENY";
        ResponseStatic.get()
            .header("X-Content-Type-Options", "nosniff")
            .header("X-Frame-Options", framePolicy)
            .header("Referrer-Policy", "strict-origin-when-cross-origin")
            .header("Content-Security-Policy",
                policy(View.nonce(request), previewFrame, request.host));
        if (contentPreview) {
            ResponseStatic.get().header("X-Robots-Tag", "noindex, nofollow");
        }
        if (request.path == "/admin" || StringTools.startsWith(request.path, "/admin/"))
            ResponseStatic.get().header("Cache-Control", "no-store");
        return next(request);
    }
}
