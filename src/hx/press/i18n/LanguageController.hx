package hx.press.i18n;

import hx.press.AdminController;
import hx.press.AdminForms;
import hx.press.CmsAccess;
import hx.press.CmsController;
import hx.press.ContentCache;
import hx.press.SiteController;
import hx.press.content.ContentTypes;
import hx.press.i18n.Languages.LanguageRecord;
import hx.press.model.Language;
import hx.press.view.View;
import hx.well.facades.DBStatic;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.ResponseBuilder;

using StringTools;

typedef LanguageForm = {
    var originalCode:String;
    var code:String;
    var name:String;
    var direction:String;
    var enabled:Bool;
    var homePageId:Int;
}

/** The Languages page: the languages a site publishes in, their order and the default. **/
class LanguageController {
    static inline var SCOPE = "language";
    static inline var URL = "/admin/languages";

    public static function index(request:Request):AbstractResponse {
        return page(request, "", 200, null);
    }

    public static function page(request:Request, error:String, status:Int,
            form:Null<LanguageForm>):AbstractResponse {
        if (!CmsAccess.can("settings")) {
            return CmsController.forbidden(request);
        }
        var redirect = AdminController.validationRedirect(request, SCOPE, error, URL);
        if (redirect != null) {
            return redirect;
        }
        var notice = switch (request.query("notice", "")) {
            case "created": "The language has been added.";
            case "saved": "The language has been updated.";
            case "ordered": "The language order has been saved.";
            case "default": "The default language has been changed.";
            case "deleted": "The language has been deleted.";
            default: "";
        };
        var languages = Languages.all();
        var codes = [for (language in languages) language.code];
        var rows:Array<Dynamic> = [];
        for (index in 0...languages.length) {
            var language = languages[index];
            var home = AdminForms.publishedContent(language.home_page_id);
            rows.push({
                code: language.code,
                name: language.name,
                direction: language.direction,
                segment: Languages.segment(language.code),
                address: language.is_default == 1 ? "/" : '/${Languages.segment(language.code)}/',
                isDefault: language.is_default == 1,
                enabled: language.enabled == 1,
                homePageId: language.home_page_id,
                homeTitle: home == null ? "" : home.title,
                moveUp: index == 0 ? "" : moved(codes, index, -1),
                moveDown: index == languages.length - 1 ? "" : moved(codes, index, 1)
            });
        }
        var editedCode = request.query("edit", "");
        var edited = Languages.find(editedCode);
        var languageForm:LanguageForm = form ?? (edited == null ? {
            originalCode: "",
            code: "",
            name: "",
            direction: "ltr",
            enabled: true,
            homePageId: 0
        } : {
            originalCode: edited.code,
            code: edited.code,
            name: edited.name,
            direction: edited.direction,
            enabled: edited.enabled == 1,
            homePageId: edited.home_page_id
            });
        var homePage = AdminForms.publishedContent(languageForm.homePageId);
        var suggestions = [
            for (code => name in Languages.names)
                if (!codes.contains(code)) {code: code, name: name}
        ];
        suggestions.sort((left, right) -> Reflect.compare(left.code, right.code));
        var props:Map<String, Dynamic> = [
            "notice" => notice,
            "siteLanguages" => rows,
            "languageForm" => languageForm,
            "homePage" => homePage,
            "suggestions" => suggestions,
            "limit" => Languages.MAX_LANGUAGES
        ];
        if (error != "") {
            props.set("errors", [SCOPE => error]);
        }
        return View.render("Admin/Languages", props).status(status);
    }

    /** The order with the language at `index` moved one place. **/
    static function moved(codes:Array<String>, index:Int, step:Int):String {
        var order = codes.copy();
        var code = order[index];
        order[index] = order[index + step];
        order[index + step] = code;
        return order.join(",");
    }

    static function formOf(request:Request):LanguageForm {
        var homeInput = AdminController.input(request, "home_page_id", 12);
        return {
            originalCode: AdminController.input(request, "original_code", 35),
            code: AdminController.input(request, "code", 35),
            name: AdminController.input(request, "name", 60),
            direction: AdminController.input(request, "direction", 3),
            enabled: AdminController.input(request, "enabled", 5) == "1",
            homePageId: Std.parseInt(homeInput) ?? 0
        };
    }

    /** Why a language code cannot be an address segment of this site, or null. **/
    static function segmentConflict(code:String, original:String):Null<String> {
        var segment = Languages.segment(code);
        var existing = Languages.bySegment(segment);
        if (existing != null && existing.code != original) {
            return "Another language already uses this code.";
        }
        if (ContentTypes.pathTaken(segment)) {
            return "This code is already an address of the site, such as a collection.";
        }
        return null;
    }

    public static function save(request:Request):AbstractResponse {
        if (!CmsAccess.can("settings")) {
            return CmsController.forbidden(request);
        }
        var form = formOf(request);
        var original = form.originalCode == "" ? null : Languages.find(form.originalCode);
        if (form.originalCode != "" && original == null) {
            return SiteController.notFound(request);
        }
        if (!Languages.validCode(form.code)) {
            return page(request,
                "Enter a language code such as en, de or pt-BR: a language, then an optional script and region.",
                422, form);
        }
        if (form.name.length < 1 || form.name.length > 60) {
            return page(request, "Enter the language name, up to 60 characters.", 422, form);
        }
        if (!["ltr", "rtl"].contains(form.direction)) {
            return page(request, "Choose a writing direction.", 422, form);
        }
        var conflict = segmentConflict(form.code, original == null ? "" : original.code);
        if (conflict != null) {
            return page(request, conflict, 422, form);
        }
        if (original == null && Languages.all().length >= Languages.MAX_LANGUAGES) {
            return page(request, "A site can publish in at most 32 languages.", 422, form);
        }
        var isDefault = original != null && original.is_default == 1;
        if (isDefault && !form.enabled) {
            return page(request,
                "The default language is always public. Choose another default language first.",
                422, form);
        }
        if (form.homePageId != 0 && AdminForms.publishedContent(form.homePageId) == null) {
            return page(request, "Choose published public content for the language’s homepage.",
                422, form);
        }
        var now = Date.now().getTime() / 1000;
        var values:Map<String, Dynamic> = [
            "name" => form.name,
            "direction" => form.direction,
            "enabled" => form.enabled ? 1 : 0,
            "home_page_id" => form.homePageId,
            "updated_epoch" => now
        ];
        DBStatic.transaction(() -> {
            if (original == null) {
                values.set("code", form.code);
                values.set("position", Languages.all().length);
                values.set("is_default", 0);
                Language.query.insert(values);
            } else {
                if (original.code != form.code) {
                    values.set("code", form.code);
                    LanguageReferences.rename(original.code, form.code);
                }
                Language.query.where("code", original.code).update(values);
            }
        });
        changed();
        var notice = original == null ? "created" : "saved";
        return ResponseBuilder.asRedirect('${URL}?notice=${notice}', 303);
    }

    public static function order(request:Request):AbstractResponse {
        if (!CmsAccess.can("settings")) {
            return CmsController.forbidden(request);
        }
        var input = AdminController.input(request, "order", 35 * Languages.MAX_LANGUAGES + 40);
        var order = input.split(",").map(code -> code.trim());
        var current = Languages.codes();
        var sorted = order.copy();
        sorted.sort(Reflect.compare);
        var expected = current.copy();
        expected.sort(Reflect.compare);
        if (sorted.join(",") != expected.join(",")) {
            return page(request, "List every language once to change their order.", 422, null);
        }
        DBStatic.transaction(() -> {
            for (index in 0...order.length) {
                Language.query.where("code", order[index]).update(["position" => index]);
            }
        });
        changed();
        return ResponseBuilder.asRedirect('${URL}?notice=ordered', 303);
    }

    public static function makeDefault(request:Request):AbstractResponse {
        if (!CmsAccess.can("settings")) {
            return CmsController.forbidden(request);
        }
        var code = AdminController.input(request, "code", 35);
        var language = Languages.find(code);
        if (language == null) {
            return page(request, "Choose one of the site’s languages.", 422, null);
        }
        DBStatic.transaction(() -> {
            Language.query.where("code", "!=", code).update(["is_default" => 0]);
            Language.query.where("code", code).update(["is_default" => 1, "enabled" => 1]);
        });
        changed();
        return ResponseBuilder.asRedirect('${URL}?notice=default', 303);
    }

    public static function remove(request:Request):AbstractResponse {
        if (!CmsAccess.can("settings")) {
            return CmsController.forbidden(request);
        }
        var language = Languages.find(request.route("code"));
        if (language == null) {
            return SiteController.notFound(request);
        }
        if (language.is_default == 1) {
            return page(request, "Choose another default language before deleting this one.", 422,
                null);
        }
        var usage = LanguageReferences.usage(language.code);
        if (usage != null) {
            return page(request, usage, 422, null);
        }
        DBStatic.transaction(() -> {
            LanguageReferences.forget(language.code);
            Language.query.where("code", language.code).delete();
        });
        changed();
        return ResponseBuilder.asRedirect('${URL}?notice=deleted', 303);
    }

    static function changed():Void {
        ContentCache.changed("languages");
        ContentCache.settingsChanged();
        ContentCache.contentChanged();
        ContentCache.changed("navigation");
    }
}
