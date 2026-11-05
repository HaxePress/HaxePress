package hx.press.handler.admin.packages;

import hx.press.CmsAccess;
import hx.press.CmsController;
import hx.press.SiteController;
import hx.press.model.ThemeDesign;
import hx.press.themes.ThemeDesignPackage;
import hx.press.themes.ThemeDesignSchema;
import hx.press.validation.ValidationResponder;
import hx.well.handler.AbstractHandler;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.RequestStatic.request;
import hx.well.http.ResponseBuilder;
import hx.well.validator.ValidatorRule;

class ExportThemeDesignHandler extends AbstractHandler implements ValidationResponder {
    public override function validate():Bool {
        if (!CmsAccess.can("extensions") || request().method == "GET") {
            return true;
        }
        var rules:Map<String, Array<ValidatorRule>> = [
            "name" => [Required, String, Min(2), Max(100)],
            "design" => [Required, String, Max(ThemeDesignSchema.MAX_BYTES)]
        ];
        return request().validate(rules);
    }

    public function validationFailed(request:Request):AbstractResponse {
        return ResponseBuilder.asJson({error: "Check the theme name and design before exporting."},
            422);
    }

    public function execute(request:Request):AbstractResponse {
        if (!CmsAccess.can("extensions")) {
            return CmsController.forbidden(request);
        }
        var id = request.route("id");
        if (!ThemeDesign.query.where("id", id).exists()) {
            return SiteController.notFound(request);
        }
        try {
            var name = request.method == "GET" ? "" : StringTools.trim(request.input("name", ""));
            if (request.method != "GET" && name.length < 2) {
                return validationFailed(request);
            }
            var source = request.method == "GET" ? "" : request.input("design", "");
            return ThemeDesignPackage.download(id, name, source);
        } catch (error:Dynamic) {
            return ResponseBuilder.asJson({error: Std.string(error)}, 422);
        }
    }
}
