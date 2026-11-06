package hx.press.access;

import haxe.Json;
import haxe.ds.StringMap;
import hx.press.Activity;
import hx.press.AdminController;
import hx.press.CmsAccess;
import hx.press.CmsController;
import hx.press.Pagination;
import hx.press.SiteController;
import hx.press.view.View;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.ResponseBuilder;

class RoleController {
    /** Role forms submit each granted capability as a `grant:<key>` field. **/
    public static inline var GRANT_PREFIX = "grant:";

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
        var notice = request.query("notice", "");
        var noticeMessage = notice == "removed" ? "The unused role has been removed." : "";
        var props = {
            roles: page.items,
            query: query,
            pagination: links,
            notice: notice,
            noticeMessage: noticeMessage
        };
        return View.render("Admin/Roles", props);
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
            creating ? "/admin/roles/new" : '/admin/roles/${role.key}/edit');
        if (redirect != null) {
            return redirect;
        }
        var grants = role == null ? [] : Roles.grants(role.key);
        var submitted = submittedForm(request, error);
        var selected = submitted == null ? grants : submittedGrants(submitted);
        var choices = Roles.capabilities("", selected);
        var protectedOwner = role != null && role.key == "owner";
        var roleForm = submitted == null ? {
            key: role == null ? "" : role.key,
            name: role == null ? "" : role.name,
            description: role == null ? "" : role.description,
            enabled: role == null || role.enabled != 0} : {
                key: role == null ? submittedText(submitted, "key") : role.key,
                name: submittedText(submitted, "name"),
                description: submittedText(submitted, "description"),
                enabled: protectedOwner || submittedText(submitted, "enabled") == "1"};
        var removable = role != null && role.system == 0 && role.owner == "";
        var actorGrants = Roles.grants(admin.role);
        var notice = request.query("notice", "");
        var props:Map<String, Dynamic> = [
            "definition" => role,
            "grants" => grants,
            "choices" => choices,
            "isNew" => creating,
            "notice" => notice,
            "noticeMessage" => notice == "saved" ? "The role has been saved." : "",
            "roleForm" => roleForm,
            "heading" => role == null ? "Role" : role.name,
            "formAction" => creating ? "/admin/roles/create" : '/admin/roles/${role.key}/save',
            "removeAction" => role == null ? "" : '/admin/roles/${role.key}/delete',
            "protectedOwner" => protectedOwner,
            "removable" => removable,
            "selected" => selected,
            "grantable" => actorGrants
        ];
        if (error != "") {
            props.set("errors", ["role" => error]);
        }
        return View.render("Admin/RoleEditor", props).status(status);
    }

    /**
        The input of a failed save: the request itself when the editor is
        rendered in its response, otherwise the input flashed by its redirect.
    **/
    static function submittedForm(request:Request, error:String):Null<Map<String, Dynamic>> {
        if (error != "") {
            return request.all();
        }
        var flashed:Dynamic = View.flashed(request, "old");
        return Std.isOfType(flashed, StringMap) ? cast flashed : null;
    }

    static function submittedText(values:Map<String, Dynamic>, key:String):String {
        var value:Dynamic = values.get(key);
        return Std.isOfType(value, String) ? value : "";
    }

    /** Whether a role form sent its capabilities as `grant:<key>` fields instead of JSON. **/
    public static function capabilityFields(request:Request):Bool {
        var value:Dynamic = request.input("capability_fields", "");
        return Std.isOfType(value, String) && value == "1";
    }

    /** The capabilities a role form submitted, one `grant:<key>` field each, or as a JSON list. **/
    public static function submittedGrants(values:Map<String, Dynamic>):Array<String> {
        var grants:Array<String> = [];
        for (key => value in values) {
            if (StringTools.startsWith(key, GRANT_PREFIX)
                && Std.isOfType(value, String)
                && value == "1"
                && grants.length < 129) {
                grants.push(key.substr(GRANT_PREFIX.length));
            }
        }
        var fields:Dynamic = values.get("capability_fields");
        if (grants.length > 0 || (Std.isOfType(fields, String) && fields == "1")) {
            grants.sort(Reflect.compare);
            return grants;
        }
        var listed:Dynamic = values.get("capabilities");
        if (!Std.isOfType(listed, String)) {
            return grants;
        }
        try {
            var source:Dynamic = Json.parse(listed);
            if (Std.isOfType(source, Array)) {
                var requested:Array<Dynamic> = source;
                for (value in requested) {
                    if (Std.isOfType(value, String) && grants.length < 129) {
                        grants.push(value);
                    }
                }
            }
        } catch (_:Dynamic) {}
        return grants;
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
