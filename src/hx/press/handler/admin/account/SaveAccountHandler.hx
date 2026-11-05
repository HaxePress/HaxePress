package hx.press.handler.admin.account;

import hx.press.AdminController;
import hx.press.CmsAccess;
import hx.press.ManagementController;
import hx.press.validation.ValidationResponder;
import hx.well.handler.AbstractHandler;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.RequestStatic.request;
import hx.well.http.ResponseBuilder;
import hx.well.validator.ValidatorRule;

class SaveAccountHandler extends AbstractHandler implements ValidationResponder {
    public override function validate():Bool {
        var current = request();

        return current.validate(["name" => [Required, String, Min(1), Max(100)]]);
    }

    public function validationFailed(request:Request):AbstractResponse {
        return ManagementController.account(request, "Enter a name using at most 100 characters.",
            422);
    }

    public function execute(request:Request):AbstractResponse {
        var name = AdminController.input(request, "name", 100);
        if (name == "") {
            return ManagementController.account(request,
                "Enter a name using at most 100 characters.", 422);
        }
        var admin = CmsAccess.current();
        admin.update(["name" => name]);
        return ResponseBuilder.asRedirect("/admin/account?notice=saved", 303);
    }
}
