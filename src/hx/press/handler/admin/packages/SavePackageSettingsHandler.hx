package hx.press.handler.admin.packages;

import hx.press.AdminController;
import hx.press.CmsAccess;
import hx.press.CmsController;
import hx.press.SiteController;
import hx.press.packages.PackageController;
import hx.press.packages.PackageData;
import hx.press.packages.PackageManager;
import hx.press.packages.PackageManifest;
import hx.press.validation.ValidationResponder;
import hx.well.handler.AbstractHandler;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.RequestStatic.request;
import hx.well.http.ResponseBuilder;
import hx.well.validator.ValidatorRule;

class SavePackageSettingsHandler extends AbstractHandler implements ValidationResponder {
    final kind:String;

    public function new(kind:String) {
        super();
        this.kind = kind;
    }

    public override function validate():Bool {
        var current = request();
        if (!CmsAccess.can("extensions")) {
            return true;
        }
        var item = PackageData.one(current.route("id"));
        if (item == null || item.kind != kind) {
            return true;
        }
        var manifest = PackageManifest.parse(item.manifest);
        var rules:Map<String, Array<ValidatorRule>> = [];
        rules.set("_context", [String, Regex("^(settings|preview)$")]);
        for (field in manifest.fields) {
            rules.set(field.key, [String, Max(2000)]);
        }
        return current.validate(rules);
    }

    public function validationFailed(request:Request):AbstractResponse {
        if (kind == "theme" && request.input("_context", "") == "preview") {
            return PackageController.preview(request,
                "Check the setting values and their length limits.", 422);
        }
        return PackageController.settings(request, kind,
            "Check the setting values and their length limits.", 422);
    }

    public function execute(request:Request):AbstractResponse {
        if (!CmsAccess.can("extensions")) {
            return CmsController.forbidden(request);
        }
        var id = request.route("id");
        var packageData = PackageData.one(id);
        if (packageData == null || packageData.kind != kind) {
            return SiteController.notFound(request);
        }
        var manifest = PackageManifest.parse(packageData.manifest);
        var input:Map<String, String> = [];
        var clear:Array<String> = [];
        for (field in manifest.fields) {
            input.set(field.key, AdminController.input(request, field.key, 2100));
            if (request.input('clear_${field.key}', "0") == "1") {
                clear.push(field.key);
            }
        }
        var admin = CmsAccess.current();
        try {
            PackageManager.configure(id, input, clear, admin.id, admin.name);
            var page = kind == "theme"
                && request.input("_context", "") == "preview" ? "preview" : "settings";
            var destination = '${PackageController.base(kind)}/${id}/${page}?notice=saved';
            return ResponseBuilder.asRedirect(destination, 303);
        } catch (error:Dynamic) {
            if (kind == "theme" && request.input("_context", "") == "preview") {
                return PackageController.preview(request, Std.string(error), 422);
            }
            return PackageController.settings(request, kind, Std.string(error), 422);
        }
    }
}
