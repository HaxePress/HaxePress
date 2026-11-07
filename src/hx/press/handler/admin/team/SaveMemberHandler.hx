package hx.press.handler.admin.team;

import hx.press.content.ContentLocks;
import haxe.io.Bytes;
import hx.press.Activity;
import hx.press.AdminController;
import hx.press.CategoryData;
import hx.press.CmsAccess;
import hx.press.CmsController;
import hx.press.ManagementController;
import hx.press.SiteSettingsStore;
import hx.press.access.Roles;
import hx.press.model.Admin;
import hx.press.validation.Flag;
import hx.press.validation.ValidationResponder;
import hx.well.facades.DBStatic;
import hx.well.facades.Hash;
import hx.well.handler.AbstractHandler;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.RequestStatic.request;
import hx.well.http.ResponseBuilder;
import hx.well.validator.ValidatorRule;

class SaveMemberHandler extends AbstractHandler implements ValidationResponder {
    public override function validate():Bool {
        var current = request();
        if (!CmsAccess.can("team")) {
            return true;
        }
        return current.validate([
            "name" => [Required, String, Min(1), Max(100)],
            "email" => [Required, String, Email, Max(254)],
            "role" => [Required, String, Max(32)],
            "password" => [String, Max(200)]
        ]);
    }

    public function validationFailed(request:Request):AbstractResponse {
        return ManagementController.team(request, "Check the member name, email and role.", 422);
    }

    public function execute(request:Request):AbstractResponse {
        if (!CmsAccess.can("team")) {
            return CmsController.forbidden(request);
        }
        return ContentLocks.run("team", () -> {
            var actor = CmsAccess.current();
            var actingId = actor.id;
            var id = Std.parseInt(AdminController.input(request, "id", 16)) ?? 0;
            var existing = id == 0 ? null : Admin.query.select(["id", "role", "active"])
                .where("id", id)
                .limit(1)
                .first();
            var name = AdminController.input(request, "name", 120);
            var email = CategoryData.key(AdminController.input(request, "email", 254));
            var role = AdminController.input(request, "role", 33);
            var active = Flag.input(request, "active") ? 1 : 0;
            var password:String = request.input("password", "");

            var validMember = name != "" && (id <= 0 || existing != null);
            var assignable = validMember && Roles.canAssign(actor.role, role);
            if (!validMember || (!assignable && !Roles.exists(role))) {
                return ManagementController.team(request,
                    "Check the member name, email and role.", 422);
            }
            if (!assignable
                || (existing != null && existing.role != role
                    && !Roles.canManage(actor.role, existing.role))) {
                return CmsController.forbidden(request);
            }
            if ((existing == null || password != "")
                && (password.length < 12 || Bytes.ofString(password).length > 72)) {
                return ManagementController.team(request,
                    "Use an initial password between 12 and 72 bytes.", 422);
            }
            if (id == actingId && password != "") {
                return ManagementController.team(request,
                    "Change your own password from Account using your current password.", 422);
            }
            if (Admin.query.where("email", email).where("id", "!=", id).exists()) {
                return ManagementController.team(request,
                    "Another account already uses this email address.", 422);
            }
            if (existing != null
                && existing.role == "owner"
                && existing.active == 1
                && (role != "owner" || active == 0)
                && !Admin.query.where("role", "owner")
                    .where("active", 1)
                    .where("id", "!=", id)
                    .exists()) {
                return ManagementController.team(request,
                    "Keep at least one active owner account.", 422);
            }
            var values:Map<String,
                Dynamic> = ["name" => name, "email" => email, "role" => role, "active" => active];
            if (password != "") {
                values.set("password", Hash.make(password));
            }
            DBStatic.transaction(() -> {
                var savedId = id;
                if (existing == null) {
                    values.set("created_at", SiteSettingsStore.timestamp());
                    savedId = Admin.query.insert(values);
                } else {
                    existing.update(values);
                }
                Activity.record("saved", "member", savedId, name);
            });
            var destination = id == actingId
                && (role != "owner" || active == 0) ? "/admin" : "/admin/team?notice=saved";
            return ResponseBuilder.asRedirect(destination, 303);
        });
    }
}
