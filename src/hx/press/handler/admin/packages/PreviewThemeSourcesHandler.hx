package hx.press.handler.admin.packages;

import haxe.Exception;
import hx.press.CmsAccess;
import hx.press.CmsController;
import hx.press.SiteController;
import hx.press.packages.PackageData;
import hx.press.themes.ThemeDesignSchema;
import hx.press.themes.ThemeFeedData;
import hx.press.validation.Flag;
import hx.press.validation.ValidationResponder;
import hx.well.handler.AbstractHandler;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.RequestStatic.request;
import hx.well.http.ResponseBuilder;
import hx.well.validator.ValidatorRule;

/** Resolve a transient design's explicitly used sources without persisting the draft. */
class PreviewThemeSourcesHandler extends AbstractHandler implements ValidationResponder {
    public override function validate():Bool {
        if (!CmsAccess.can("extensions")) {
            return true;
        }
        return request().validate([
            "design" => [Required, String, Max(ThemeDesignSchema.MAX_BYTES)],
            "scope" => [Required, String, Max(81)],
            "normalize" => [String, Regex("^1$")]
        ]);
    }

    public function validationFailed(request:Request):AbstractResponse {
        return ResponseBuilder.asJson({error: "Choose a valid design and preview template."}, 422);
    }

    public function execute(request:Request):AbstractResponse {
        if (!CmsAccess.can("extensions")) {
            return CmsController.forbidden(request);
        }
        var theme = PackageData.one(request.route("id"));
        if (theme == null || theme.kind != "theme") {
            return SiteController.notFound(request);
        }
        try {
            var document = ThemeDesignSchema.parse(request.input("design", ""));
            var scope = request.input("scope", "Home");
            var exists = StringTools.startsWith(scope,
                "@") ? Reflect.hasField(document.components,
                    scope.substr(1)) : Reflect.hasField(document.templates, scope);
            if (!exists) {
                throw new Exception("Choose a template or component in this design.");
            }
            var feeds = ThemeFeedData.resolve({design: document}, scope);
            if (Flag.input(request, "normalize")) {
                return ResponseBuilder.asJson({document: document, feeds: feeds});
            }
            return ResponseBuilder.asJson({feeds: feeds});
        } catch (error:Dynamic) {
            return ResponseBuilder.asJson({error: Std.string(error)}, 422);
        }
    }
}
