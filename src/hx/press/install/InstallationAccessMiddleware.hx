package hx.press.install;

import hx.well.http.Request;
import hx.well.http.Response;
import hx.well.http.ResponseBuilder;
import hx.well.middleware.AbstractMiddleware;

class InstallationAccessMiddleware extends AbstractMiddleware {
    public function handle(request:Request, next:Request->Null<Response>):Null<Response> {
        if (!InstallationState.pending) {
            return ResponseBuilder.asString("Not found.", 404);
        }
        if (!InstallationState.allowed(request)) {
            return InstallationController.locked(request);
        }
        return next(request);
    }
}
