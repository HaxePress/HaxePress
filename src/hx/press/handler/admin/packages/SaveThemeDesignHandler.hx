package hx.press.handler.admin.packages;

import hx.press.CmsAccess;
import hx.press.CmsController;
import hx.press.themes.ThemeStudio;
import hx.press.themes.ThemeDesignSchema;
import hx.press.packages.PackageManager;
import hx.press.validation.ValidationResponder;
import hx.well.facades.Inertia;
import hx.well.handler.AbstractHandler;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.RequestStatic.request;
import hx.well.http.ResponseBuilder;
import hx.well.validator.ValidatorRule;

class SaveThemeDesignHandler extends AbstractHandler implements ValidationResponder {
    final creating:Bool;

    public function new(creating:Bool = false) {
        super();
        this.creating = creating;
    }

    public override function validate():Bool {
        if (!CmsAccess.can("extensions")) {
            return true;
        }
        var rules:Map<String,
            Array<ValidatorRule>> = ["name" => [Required, String, Min(2), Max(100)]];
        if (creating) {
            rules.set("starter", [Required, String, Regex("^(content|blank)$")]);
            rules.set("design", [String, Max(ThemeDesignSchema.MAX_BYTES)]);
        } else {
            rules.set("design", [Required, String, Max(ThemeDesignSchema.MAX_BYTES)]);
            rules.set("version", [Required, String, Regex("^[1-9][0-9]{0,8}$")]);
            rules.set("action", [Required, String, Regex("^(save|publish|launch)$")]);
        }
        return request().validate(rules);
    }

    public function validationFailed(request:Request):AbstractResponse {
        if (creating) {
            var props = {
                baseDocument: ThemeDesignSchema.starter(true),
                errors: {name: "Enter a theme name between 2 and 100 characters and choose a starting layout."}
            };
            return Inertia.render("Admin/ThemeCreate", props).status(422);
        }
        return
            ResponseBuilder.asJson({error: "Check the theme name, design and version before saving."},
                422);
    }

    public function execute(request:Request):AbstractResponse {
        if (!CmsAccess.can("extensions")) {
            return CmsController.forbidden(request);
        }
        var admin = CmsAccess.current();
        var name = StringTools.trim(request.input("name", ""));
        if (name.length < 2) {
            return validationFailed(request);
        }
        try {
            if (creating) {
                var id = ThemeStudio.create(name, request.input("starter", "content") == "blank",
                    admin.id, admin.name, request.input("design", ""));
                return ResponseBuilder.asRedirect('/admin/themes/${id}/design', 303);
            }
            var version = Std.parseInt(request.input("version", "0")) ?? 0;
            var action = request.input("action", "save");
            var publish = action != "save";
            var saved = ThemeStudio.save(request.route("id"), name, request.input("design", ""),
                version, publish, admin.id, admin.name);
            var active:Null<Bool> = null;
            if (action == "launch") {
                try {
                    PackageManager.enable(request.route("id"), admin.id, admin.name);
                    active = true;
                } catch (activationError:Dynamic) {
                    return ResponseBuilder.asJson({
                        version: saved.version,
                        publishedVersion: saved.published_version,
                        active: false,
                        error: 'Your design was published, but the website could not be activated. ${Std.string(activationError)}'
                    }, 422);
                }
            }
            return ResponseBuilder.asJson({
                version: saved.version,
                publishedVersion: saved.published_version,
                active: active,
                notice: action == "launch" ? "Your website is live." : publish ? "Theme published." : "Draft saved."
            });
        } catch (error:Dynamic) {
            if (creating) {
                return Inertia.render("Admin/ThemeCreate", {
                    baseDocument: ThemeDesignSchema.starter(true),
                    errors: {name: Std.string(error)}
                }).status(422);
            }
            return ResponseBuilder.asJson({error: Std.string(error)}, 422);
        }
    }
}
