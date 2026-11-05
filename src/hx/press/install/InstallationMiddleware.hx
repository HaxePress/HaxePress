package hx.press.install;

import hx.well.http.Request;
import hx.well.http.Response;
import hx.well.http.ResponseBuilder;
import hx.well.middleware.AbstractMiddleware;

/** No database, sessions or application services run for a disallowed first-install request. */
class InstallationMiddleware extends AbstractMiddleware {
    public function handle(request:Request, next:Request->Null<Response>):Null<Response> {
        if (!InstallationState.pending) {
            return next(request);
        }
        var path = request.path;
        if (StringTools.startsWith(path, "/build/assets/")
            || StringTools.startsWith(path, "/fonts/")
            || path == "/favicon.svg"
            || path == "/favicon.ico"
            || path == "/admin/install"
            || StringTools.startsWith(path, "/admin/install/")) {
            return next(request);
        }
        if (!InstallationState.allowed(request)) {
            return InstallationController.locked(request);
        }
        return ResponseBuilder.asRedirect("/admin/install", 303);
    }
}
