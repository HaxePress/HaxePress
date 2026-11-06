package hx.press.handler;

import hx.press.validation.ValidationResponder;
import hx.well.handler.AbstractHandler;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.route.RouteElement;
import hx.well.template.StatusTemplate;
import hx.well.type.AttributeType;

/** Keep each endpoint's JSON or form-redirect error response after native validate() returns false. */
class ValidationErrorHandler extends AbstractHandler {
    public function execute(request:Request):AbstractResponse {
        var route:RouteElement = request.getAttribute(AttributeType.RouteElement);
        var handler = route == null ? null : route.getHandler();
        if (Std.isOfType(handler, ValidationResponder)) {
            var responder:ValidationResponder = cast handler;
            return responder.validationFailed(request);
        }
        return new StatusTemplate(422).execute(request);
    }
}
