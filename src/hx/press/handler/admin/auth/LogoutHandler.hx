package hx.press.handler.admin.auth;

import hx.well.facades.Inertia;
import hx.well.handler.AbstractHandler;
import hx.well.http.Request;
import hx.well.http.AbstractResponse;
import hx.well.http.ResponseBuilder;
import hx.well.http.RequestStatic.auth;

class LogoutHandler extends AbstractHandler {
    public function execute(request:Request):AbstractResponse {
        auth("admin").logout();
        Inertia.clearHistory();
        return ResponseBuilder.asRedirect("/admin/login", 303);
    }
}
