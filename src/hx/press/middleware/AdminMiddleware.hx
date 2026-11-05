package hx.press.middleware;

import hx.well.middleware.AbstractMiddleware;
import hx.well.http.Request;
import hx.well.http.Response;
import hx.well.http.ResponseBuilder;
import hx.press.CmsAccess;

class AdminMiddleware extends AbstractMiddleware {
    public function handle(request:Request, next:Request->Null<Response>):Null<Response> {
        if (CmsAccess.current() != null) {
            return next(request);
        }
        return ResponseBuilder.asRedirect("/admin/login", 303);
    }
}
