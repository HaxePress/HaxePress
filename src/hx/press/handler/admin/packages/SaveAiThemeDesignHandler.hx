package hx.press.handler.admin.packages;

import hx.press.themes.ThemeAiAccess;
import hx.press.themes.ThemeAiAccess.ThemeAiActor;
import hx.press.themes.ThemeDesignSchema;
import hx.press.themes.ThemeStudio;
import hx.press.validation.PositiveInt;
import hx.press.validation.ValidationResponder;
import hx.well.handler.AbstractHandler;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.RequestStatic.request;
import hx.well.http.ResponseBuilder;
import hx.well.validator.ValidatorRule;

class SaveAiThemeDesignHandler extends AbstractHandler implements ValidationResponder {
    public override function validate():Bool {
        var rules:Map<String, Array<ValidatorRule>> = [
            "name" => [Required, String, Min(2), Max(100)],
            "design" => [Required, String, Max(ThemeDesignSchema.MAX_BYTES)],
            "version" => [Required, String, Custom("cms.positive_int")]
        ];
        return request().validate(rules);
    }

    public function validationFailed(request:Request):AbstractResponse {
        return
            ResponseBuilder.asJson({error: "Check the theme name, design and expected version."},
                422);
    }

    public function execute(request:Request):AbstractResponse {
        var actor:ThemeAiActor = request.getAttribute(ThemeAiAccess.ACTOR);
        if (actor == null) {
            return ResponseBuilder.asJson({error: "An AI connection is required."}, 401);
        }
        var name = StringTools.trim(request.input("name", ""));
        if (name.length < 2) {
            return validationFailed(request);
        }
        try {
            var result = ThemeStudio.save(request.route("id"), name, request.input("design", ""),
                PositiveInt.parse(request.input("version", "")) ?? 0, false, actor.id,
                '${actor.name} (AI)');
            return ResponseBuilder.asJson({
                version: result.version,
                publishedVersion: result.published_version,
                editorUrl: '/admin/themes/${request.route("id")}/design'
            });
        } catch (error:Dynamic) {
            return ResponseBuilder.asJson({error: Std.string(error)}, 422);
        }
    }
}
