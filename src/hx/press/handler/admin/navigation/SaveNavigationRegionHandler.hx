package hx.press.handler.admin.navigation;

import hx.press.validation.Flag;
import hx.well.handler.AbstractHandler;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.RequestStatic.request;
import hx.well.http.ResponseBuilder;
import hx.well.validator.ValidatorRule;
import hx.press.validation.ValidationResponder;
import hx.press.AdminController;
import hx.press.CmsAccess;
import hx.press.CmsController;
import hx.press.ManagementController;
import hx.press.navigation.NavigationRegions;

class SaveNavigationRegionHandler extends AbstractHandler implements ValidationResponder {
    public override function validate():Bool {
        if (!CmsAccess.can("navigation")) {
            return true;
        }
        return request().validate([
            "key" => [Required, String, Min(1), Max(40)],
            "name" => [Required, String, Min(1), Max(100)],
            "max_links" => [Required, String, Custom("cms.positive_int", [999])],
            "enabled" => [String, Custom("cms.flag")]
        ]);
    }

    public function validationFailed(request:Request):AbstractResponse {
        return ManagementController.navigation(request, "Choose a valid navigation region limit.",
            422);
    }

    public function execute(request:Request):AbstractResponse {
        if (!CmsAccess.can("navigation")) {
            return CmsController.forbidden(request);
        }
        var key = AdminController.input(request, "key", 41);
        try {
            var maximum = Std.parseInt(AdminController.input(request, "max_links", 3));
            NavigationRegions.save(key, AdminController.input(request, "name", 101), maximum,
                Flag.input(request, "enabled"));
            return
                ResponseBuilder.asRedirect('/admin/navigation?location=${StringTools.urlEncode(key)}&notice=saved',
                    303);
        } catch (error:Dynamic) {
            return ManagementController.navigation(request, Std.string(error), 422);
        }
    }
}
