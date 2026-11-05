package hx.press.handler.admin.packages;

import hx.press.CmsAccess;
import hx.press.CmsController;
import hx.press.SiteController;
import hx.press.model.ThemeDesign;
import hx.press.themes.ThemeAiPermissions;
import hx.press.validation.ValidationResponder;
import hx.well.handler.AbstractHandler;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.RequestStatic.request;
import hx.well.http.ResponseBuilder;
import hx.well.validator.ValidatorRule;

class SaveThemeAiPermissionsHandler extends AbstractHandler implements ValidationResponder {
    public override function validate():Bool {
        if (!CmsAccess.can("extensions")) {
            return true;
        }
        var rules:Map<String, Array<ValidatorRule>> = [
            "read" => [Required, String, Regex("^[01]$")],
            "edit" => [Required, String, Regex("^[01]$")],
            "media" => [Required, String, Regex("^[01]$")]
        ];
        return request().validate(rules);
    }

    public function validationFailed(request:Request):AbstractResponse {
        return ResponseBuilder.asJson({error: "Choose valid AI permissions."}, 422);
    }

    public function execute(request:Request):AbstractResponse {
        if (!CmsAccess.can("extensions")) {
            return CmsController.forbidden(request);
        }
        var id = request.route("id");
        if (!ThemeDesign.query.where("id", id).exists()) {
            return SiteController.notFound(request);
        }
        var inputs = request.only("read", "edit", "media");
        var admin = CmsAccess.current();
        ThemeAiPermissions.save(id, admin.id, {
            read: inputs.get("read") == "1",
            edit: inputs.get("edit") == "1",
            media: inputs.get("media") == "1" && CmsAccess.can("media")
        });
        return ResponseBuilder.asJson({
            permissions: ThemeAiPermissions.forAdmin(id, admin.id, CmsAccess.can("media"))
        }).header("Cache-Control", "private, no-store");
    }
}
