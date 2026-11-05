package hx.press;

import hx.well.facades.Inertia;
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
        if (message == "" || !Inertia.isInertiaRequest(request)) {
            return null;
        }

        var errors = [scope => message];
        Inertia.flash("errors", errors);
        return ResponseBuilder.asRedirect(url, 303);
    }

    public static function loginPage(request:Request):AbstractResponse {
        if (CmsAccess.current() != null) {
            return ResponseBuilder.asRedirect("/admin");
        }

        var props = {email: ""};
        return Inertia.render("Admin/Login", props);
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
        return Inertia.render("Admin/Login", props).status(status);
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
        var categoryForm = form ?? {id: "", name: ""};
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

        return Inertia.render("Admin/Categories", props).status(status);
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

        var props:Map<String, Dynamic> = ["notice" => notice];

        if (error != "") {
            props.set("errors", [scope => error]);
        }

        return Inertia.render("Admin/Settings", props).status(status);
    }
}
