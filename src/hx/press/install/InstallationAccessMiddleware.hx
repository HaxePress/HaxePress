package hx.press.install;

import hx.well.http.Request;
import hx.well.http.Response;
import hx.well.middleware.AbstractMiddleware;

class InstallationAccessMiddleware extends AbstractMiddleware {
    public function handle(request:Request, next:Request->Null<Response>):Null<Response> {
        if (!InstallationState.pending) {
            abort(404);
        }
        if (!InstallationState.allowed(request)) {
            return InstallationController.locked(request);
        }
        return next(request);
    }
}
