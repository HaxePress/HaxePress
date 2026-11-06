package hx.press.handler.install;

import haxe.io.Bytes;
import hx.press.AdminController;
import hx.press.install.InstallationController;
import hx.press.install.InstallationController.SetupAdministrator;
import hx.press.validation.ValidationResponder;
import hx.well.handler.AbstractHandler;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.RequestStatic.request;
import hx.well.http.ResponseBuilder;

/**
    The administrator step of the installer: checks the site name and the
    account, keeps them in the session and shows the review step. The
    installation itself runs when the review is confirmed.
**/
class ReviewInstallationHandler extends AbstractHandler implements ValidationResponder {
    public override function validate():Bool {
        return request().validate([
            "site_name" => [Required, String, Min(2), Max(100), Regex("^[^\\x00-\\x1f\\x7f]+$")],
            "admin_name" => [Required, String, Min(2), Max(100), Regex("^[^\\x00-\\x1f\\x7f]+$")],
            "admin_email" => [Required, String, Email, Max(254), Regex("^[^\\x00-\\x1f\\x7f]+$")],
            "admin_password" => [
                Required,
                String,
                Min(12),
                Custom("cms.byte_length", [72]),
                Regex("^[^\\x00-\\x1f\\x7f]+$")
            ],
            "confirm_password" => [Required, String, Min(1)]
        ]);
    }

    public function validationFailed(request:Request):AbstractResponse {
        var password:Dynamic = request.input("admin_password", "");
        var bytes = Std.isOfType(password, String) ? Bytes.ofString(password).length : 0;
        var message = bytes < 12
            || bytes > 72 ? "Use a password between 12 and 72 bytes." : "Check the site and administrator fields. Use a password between 12 and 72 bytes.";
        return failed(request, message, "administrator");
    }

    public function execute(request:Request):AbstractResponse {
        var inputs = request.only("site_name", "admin_name", "admin_email", "admin_password",
            "confirm_password");
        var siteName = StringTools.trim(inputs.get("site_name"));
        var adminName = StringTools.trim(inputs.get("admin_name"));
        if (siteName.length < 2 || adminName.length < 2) {
            return validationFailed(request);
        }
        if (inputs.get("admin_password") != inputs.get("confirm_password")) {
            return failed(request, "The passwords do not match.", "administrator");
        }
        if (InstallationController.verifiedDatabase(request) == null) {
            return failed(request, "Verify the database connection again before continuing.",
                "database");
        }
        var administrator:SetupAdministrator = {
            site_name: siteName,
            admin_name: adminName,
            admin_email: StringTools.trim(inputs.get("admin_email")),
            admin_password: inputs.get("admin_password")
        };
        request.session.put(InstallationController.ADMINISTRATOR_KEY, administrator);
        return ResponseBuilder.asRedirect("/admin/install?step=review", 303)
            .header("Cache-Control", "private, no-store");
    }

    static function failed(request:Request, message:String, step:String):AbstractResponse {
        var redirect = AdminController.validationRedirect(request, "setup", message,
            '/admin/install?step=${step}');
        if (redirect != null) {
            return redirect.header("Cache-Control", "private, no-store");
        }
        return ResponseBuilder.asJson({error: message}, 422)
            .header("Cache-Control", "private, no-store");
    }
}
