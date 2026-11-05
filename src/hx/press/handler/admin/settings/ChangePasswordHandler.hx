package hx.press.handler.admin.settings;

import hx.well.http.RequestStatic.request;
import hx.well.validator.ValidatorRule;
import hx.press.validation.ValidationResponder;
import hx.well.handler.AbstractHandler;
import hx.well.http.Request;
import hx.well.http.AbstractResponse;
import hx.well.http.ResponseBuilder;
import hx.well.facades.Hash;
import hx.press.AdminController;
import hx.press.CmsAccess;
import hx.press.ManagementController;
import hx.press.Activity;

class ChangePasswordHandler extends AbstractHandler implements ValidationResponder {
    public override function validate():Bool {
        return request().validate([
            "current_password" => [Required, String, Min(1)],
            "new_password" => [Required, String, Min(12), Custom("cms.byte_length", [72])],
            "confirm_password" => [Required, String, Min(1)]
        ]);
    }

    public function validationFailed(request:Request):AbstractResponse {
        return invalid(request, "Use a password between 12 and 72 bytes.");
    }

    public function execute(request:Request):AbstractResponse {
        var admin = CmsAccess.current();
        var values = request.only("current_password", "new_password", "confirm_password");
        var current:String = values.get("current_password");
        var password:String = values.get("new_password");
        var confirm:String = values.get("confirm_password");
        if (!Hash.check(current, admin.password)) {
            return invalid(request, "Your current password is incorrect.");
        }

        if (password != confirm) {
            return invalid(request, "The new passwords do not match.");
        }
        var hash = Hash.make(password);
        admin.update(["password" => hash]);
        request.session.regenerate();
        request.session.put("auth_version", hash);
        Activity.record("password updated", "member", admin.id, admin.name);
        return ResponseBuilder.asRedirect(destination(request) + "?notice=password", 303);
    }

    static function destination(request:Request):String {
        return request.input("return_to", "") == "account"
            || !CmsAccess.can("settings") ? "/admin/account" : "/admin/settings";
    }

    static function invalid(request:Request, message:String):AbstractResponse {
        if (destination(request) == "/admin/account") {
            return ManagementController.account(request, message, 422);
        }
        return AdminController.settingsForm(request, message, "", 422, "password");
    }
}
