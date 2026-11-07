package hx.press.handler.admin.role;

import hx.press.validation.Flag;
import hx.well.handler.AbstractHandler;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.RequestStatic.request;
import hx.well.http.ResponseBuilder;
import hx.well.validator.ValidatorRule;
import hx.press.validation.ValidationResponder;
import hx.press.AdminController;
import hx.press.CmsAccess;
import hx.press.CmsController;
import hx.press.Activity;
import haxe.Json;
import haxe.Exception;
import hx.press.access.RoleController;
import hx.press.access.Roles;

class SaveRoleHandler extends AbstractHandler implements ValidationResponder {
    public override function validate():Bool {
        var current = request();
        if (!CmsAccess.can("roles")) {
            return true;
        }
        var routeKey = current.route("key");
        if (routeKey != null && !Roles.canManage(CmsAccess.current().role, routeKey)) {
            return true;
        }
        var rules:Map<String, Array<ValidatorRule>> = [
            "key" => [Required, String, Min(1), Max(32)],
            "name" => [Required, String, Min(1), Max(100)],
            "description" => [String, Max(500)],
            "enabled" => [String, Custom("cms.flag")]
        ];
        if (!RoleController.capabilityFields(current)) {
            rules.set("capabilities", [Required, String, Max(16000)]);
        }
        return current.validate(rules);
    }

    public function validationFailed(request:Request):AbstractResponse {
        var creating = request.route("key") == null;
        return RoleController.editor(request, creating,
            "Check the role key, label and permission limits.", 422);
    }

    public function execute(request:Request):AbstractResponse {
        if (!CmsAccess.can("roles")) {
            return CmsController.forbidden(request);
        }
        var creating = request.route("key") == null;
        try {
            var key = AdminController.input(request, "key", 33);
            if ((!creating && request.route("key") != key) || !Roles.validKey(key)) {
                throw new Exception("Use a unique stable role key.");
            }
            var actor = CmsAccess.current();
            if (!creating && !Roles.canManage(actor.role, key)) {
                return CmsController.forbidden(request);
            }
            var requested:Array<Dynamic>;
            if (RoleController.capabilityFields(request)) {
                requested = cast RoleController.submittedGrants(request.all());
                if (requested.length > 128) {
                    throw new Exception("A role can contain at most 128 capabilities.");
                }
            } else {
                var source:Dynamic = Json.parse(AdminController.input(request, "capabilities",
                    16000));
                if (!(source is Array)) {
                    throw new Exception("Choose a list of role capabilities.");
                }
                requested = source;
            }
            var grants:Array<String> = [];
            var actorGrants = CmsAccess.capabilities(actor.role);
            for (value in requested) {
                if (!(value is String)
                    || (!actorGrants.contains("*") && !actorGrants.contains(value))) {
                    throw new Exception("A role cannot grant capabilities that your account does not hold.");
                }
                grants.push(value);
            }
            Roles.save(key, AdminController.input(request, "name", 101),
                AdminController.input(request, "description", 501),
                Flag.input(request, "enabled"), grants, creating);
            Activity.record("saved", "role", 0, key);
            return ResponseBuilder.asRedirect('/admin/roles/${key}/edit?notice=saved', 303);
        } catch (error:Dynamic) {
            return RoleController.editor(request, creating, Std.string(error), 422);
        }
    }
}
