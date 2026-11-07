package hx.press;

import hx.press.ai.AdminMcpAccess;
import hx.press.validation.PositiveInt;
import hx.press.view.View;
import hx.press.media.MediaReferences;
import hx.press.AdminForms;
import hx.press.SiteSettingsStore;
import hx.press.model.Category;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.Response;
import hx.well.http.ResponseBuilder;
import hx.press.CmsAccess;
import hx.press.CmsController;
import hx.press.DashboardController;

using StringTools;

class AdminController {
    public static function input(request:Request, key:String, limit:Int = 10000):String {
        var value:Dynamic = request.input(key, "");

        if (!Std.isOfType(value, String)) {
            return "";
        }

        return Std.string(value).substr(0, limit).trim();
    }

    public static function validationRedirect(request:Request, scope:String, message:String,
            url:String):Null<Response> {
        if (message == "" || !View.redirectsValidation(request)
            || request.getAttribute(AdminMcpAccess.INTERNAL, false)) {
            return null;
        }

        var errors = [scope => message];
        View.flash("errors", errors);
        View.flash("old", submittedInput(request));
        return ResponseBuilder.asRedirect(url, 303);
    }

    /** The submitted form values without secrets, shown again after a failed submission. **/
    public static function submittedInput(request:Request):Map<String, String> {
        var values:Map<String, String> = [];
        for (key => value in request.all()) {
            var lowered = key.toLowerCase();
            if (key == "_token" || lowered.indexOf("password") >= 0
                || lowered.indexOf("secret") >= 0) {
                continue;
            }
            if (Std.isOfType(value, String) && (value : String).length <= 20000) {
                values.set(key, value);
            }
        }
        return values;
    }

    public static function loginPage(request:Request):AbstractResponse {
        if (CmsAccess.current() != null) {
            return ResponseBuilder.asRedirect("/admin");
        }

        var props = {email: ""};
        return View.render("Admin/Login", props);
    }

    public static function loginForm(request:Request, error:String,
            status:Int = 200):AbstractResponse {
        var redirect = validationRedirect(request, "credentials", error, "/admin/login");

        if (redirect != null) {
            return redirect;
        }

        var email = input(request, "email", 254);
        var errors = ["credentials" => error];

        var props = {email: email, errors: errors};
        return View.render("Admin/Login", props).status(status);
    }

    public static function dashboard(request:Request):AbstractResponse {
        return DashboardController.index(request);
    }

    static function notice(key:String):String {
        return switch (key) {
            case "saved": "Your content has been saved.";
            case "deleted": "The content item has been deleted.";
            case "settings": "Your settings have been saved.";
            case "password": "Your password has been updated.";
            default: "";
        };
    }

    public static function categoryList(request:Request, error:String = "", status:Int = 200,
            form:Dynamic = null):AbstractResponse {
        if (!CmsAccess.can("taxonomy")) {
            return CmsController.forbidden(request);
        }
        var redirect = validationRedirect(request, "category", error, "/admin/categories");

        if (redirect != null) {
            return redirect;
        }

        var message = switch (request.query("notice", "")) {
            case "created": "The category has been added.";
            case "renamed": "The category has been updated.";
            case "deleted": "The category has been deleted.";
            default: "";
        };
        var query = request.query("q", "").trim().substr(0, 80);
        var cursor = Pagination.cursor(request);
        var page = CategoryData.page(query, cursor);
        var total = CategoryData.count(query);
        var links = Pagination.links("/admin/categories", ["q" => query], page, cursor, total,
            category -> category.id, category -> null);
        var categories = page.items;
        var editedId = PositiveInt.parse(request.query("edit", ""));
        var editedCategory = form == null
            && editedId != null ? Category.query.select(["id", "name"])
                .where("id", editedId)
                .limit(1)
                .first() : null;
        var categoryForm = form ?? (editedCategory == null ? {id: "", name: ""} : {
            id: Std.string(editedCategory.id),
            name: editedCategory.name
        });
        var props:Map<String, Dynamic> = [
            "categoryList" => categories,
            "notice" => message,
            "categoryForm" => categoryForm,
            "total" => total,
            "query" => query,
            "pagination" => links
        ];

        if (error != "") {
            props.set("errors", ["category" => error]);
        }

        return View.render("Admin/Categories", props).status(status);
    }

    public static function settings(request:Request):AbstractResponse {
        if (!CmsAccess.can("settings")) {
            return CmsController.forbidden(request);
        }
        var message = notice(request.query("notice", ""));
        return settingsForm(request, "", message);
    }

    public static function settingsForm(request:Request, error:String, notice:String = "",
            status:Int = 200, scope:String = "settings"):AbstractResponse {
        if (!CmsAccess.can("settings")) {
            return CmsController.forbidden(request);
        }
        var redirect = validationRedirect(request, scope, error, "/admin/settings");

        if (redirect != null) {
            return redirect;
        }

        var settings = SiteSettingsStore.settings();
        var resubmitted = AdminForms.resubmitted(request, "site_name");
        var value = (key:String) -> {
            var stored = settings.get(key) ?? "";
            return resubmitted ? AdminForms.old(request, key, stored) : stored;
        };
        var settingsForm = {
            site_name: value("site_name"),
            site_logo: value("site_logo"),
            publisher_name: value("publisher_name"),
            description: value("description"),
            about_site: value("about_site"),
            locale: value("locale"),
            home_mode: value("home_mode"),
            home_type: value("home_type"),
            home_page: value("home_page"),
            home_size: value("home_size"),
            home_template: value("home_template")
        };
        var homeCollections = AdminForms.publicCollections();
        var homeTypeKnown = Lambda.exists(homeCollections,
            collection -> collection.key == settingsForm.home_type);
        var homePageId = Std.parseInt(settingsForm.home_page) ?? 0;
        var homePage = AdminForms.publishedContent(homePageId);
        var props:Map<String, Dynamic> = [
            "notice" => notice,
            "settingsForm" => settingsForm,
            "homeCollections" => homeCollections,
            "homeTypeKnown" => homeTypeKnown,
            "homePage" => homePage,
            "logoRules" => MediaReferences.rules()
        ];

        if (error != "") {
            props.set("errors", [scope => error]);
        }

        return View.render("Admin/Settings", props).status(status);
    }
}
