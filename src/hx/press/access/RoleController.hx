package hx.press.access;

import hx.press.Activity;
import hx.press.AdminController;
import hx.press.CmsAccess;
import hx.press.CmsController;
import hx.press.Pagination;
import hx.press.SiteController;
import hx.well.facades.Inertia;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.ResponseBuilder;

class RoleController {
    public static function index(request:Request):AbstractResponse {
        if (!CmsAccess.can("roles")) {
            return CmsController.forbidden(request);
        }
        var query = StringTools.trim(request.query("q", "")).substr(0, 100);
        var cursor = Pagination.cursor(request, true);
        var page = Roles.page(query, cursor);
        var count = Roles.count(query);
        var links = Pagination.links("/admin/roles", ["q" => query], page, cursor, count,
            role -> role.key, role -> null);
        var props = {
            roles: page.items,
            query: query,
            pagination: links,
            notice: request.query("notice", "")
        };
        return Inertia.render("Admin/Roles", props);
    }

    public static function editor(request:Request, creating:Bool = false, error:String = "",
            status:Int = 200):AbstractResponse {
        if (!CmsAccess.can("roles")) {
            return CmsController.forbidden(request);
        }
        var role = creating ? null : Roles.find(request.route("key"), false);
        if (!creating && role == null) {
            return SiteController.notFound(request);
        }
        var admin = CmsAccess.current();
        if (role != null && !Roles.canManage(admin.role, role.key)) {
            return CmsController.forbidden(request);
        }
        var redirect = AdminController.validationRedirect(request, "role", error,
            creating ? "/admin/roles/new" : "/admin/roles/" + role.key + "/edit");
        if (redirect != null) {
            return redirect;
        }
        var grants = role == null ? [] : Roles.grants(role.key);
        var props:Map<String, Dynamic> = [
            "definition" => role,
            "grants" => grants,
            "choices" => Roles.capabilities("", grants),
            "isNew" => creating,
            "notice" => request.query("notice", "")
        ];
        if (error != "") {
            props.set("errors", ["role" => error]);
        }
        return Inertia.render("Admin/RoleEditor", props).status(status);
    }

    public static function remove(request:Request):AbstractResponse {
        if (!CmsAccess.can("roles")) {
            return CmsController.forbidden(request);
        }
        var key = request.route("key");
        if (!Roles.canManage(CmsAccess.current().role, key)) {
            return CmsController.forbidden(request);
        }
        try {
            Roles.remove(key);
            Activity.record("deleted", "role", 0, key);
            return ResponseBuilder.asRedirect("/admin/roles?notice=removed", 303);
        } catch (error:Dynamic) {
            return editor(request, false, Std.string(error), 422);
        }
    }

    public static function capabilities(request:Request):AbstractResponse {
        if (!CmsAccess.can("roles")) {
            return ResponseBuilder.asJson({error: "Access restricted."}, 403);
        }
        return ResponseBuilder.asJson({
            choices: Roles.capabilities(StringTools.trim(request.query("q", "")).substr(0, 100))
        });
    }
}
