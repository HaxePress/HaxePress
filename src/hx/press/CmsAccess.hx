package hx.press;

import hx.well.http.RequestStatic.auth;
import hx.press.model.Admin;
import hx.well.http.RequestStatic;
import hx.press.access.Roles;
import hx.press.content.ContentTypes;
import hx.press.model.ContentType;

class CmsAccess {
    public static function current():Null<Admin> {
        var request = RequestStatic.request();
        if (request == null) {
            return null;
        }
        var guard = auth("admin");
        if (!guard.check()) {
            return null;
        }
        var admin:Admin = guard.user();
        if (admin == null
            || admin.active != 1
            || Roles.find(admin.role) == null
            || request.session.get("auth_version", "") != admin.password) {
            return null;
        }
        return admin;
    }

    public static function can(capability:String):Bool {
        var admin = current();
        if (admin == null) {
            return false;
        }
        var grants = capabilities(admin.role);
        return grants.contains("*") || grants.contains(capability);
    }

    public static function capabilities(role:String):Array<String> {
        return Roles.find(role) == null ? [] : Roles.grants(role);
    }

    public static function canCollection(kind:String):Bool {
        var type = ContentTypes.find(kind);
        return type != null && can(type.capability);
    }

    public static function hasContentAccess():Bool {
        var admin = current();
        if (admin == null) {
            return false;
        }
        var grants = capabilities(admin.role);
        if (grants.contains("*")) {
            return true;
        }
        return ContentCache.remember("structure", "accessible-collections",
            [grants, ContentTypes.revision()], () -> {
                return ContentTypes.accessible(ContentType.query.select(["key"]), grants).exists();
            });
    }

    public static function canEdit(authorId:Int):Bool {
        var admin = current();
        return admin != null && (can("edit_others") || admin.id == authorId);
    }
}
