package hx.press.access;

import haxe.Exception;
import hx.press.ContentCache;
import hx.press.Pagination;
import hx.press.Pagination.PageCursor;
import hx.press.content.ContentLocks;
import hx.press.data.QueryPage;
import hx.press.model.Admin;
import hx.press.model.Capability;
import hx.press.model.InstalledPackage;
import hx.press.model.Role;
import hx.press.model.RoleGrant;
import hx.well.database.query.QueryBuilder;
import hx.well.facades.DBStatic;

typedef RoleRecord = {
    var key:String;
    var name:String;
    var description:String;
    var enabled:Int;
    var system:Int;
    var owner:String;
}

typedef CapabilityRecord = {
    var key:String;
    var name:String;
    var group_name:String;
    var owner:String;
}

class Roles {
    static final columns = ["key", "name", "description", "enabled", "system", "owner"];

    static function active(query:QueryBuilder<Role>):QueryBuilder<Role> {
        var owners = InstalledPackage.query.select(["id"])
            .where("enabled", 1)
            .where("restart_required", 0);
        return query.where("enabled", 1).where(visibility -> {
            visibility.where("owner", "").orWhere(plugin -> plugin.whereInQuery("owner", owners));
        });
    }

    public static function validKey(key:String):Bool {
        return key != null && ~/^[a-z][a-z0-9_]{0,31}(?![\s\S])/.match(key);
    }

    static function byKey(key:String, activeOnly:Bool):QueryBuilder<Role> {
        var query = Role.query.where("key", key);
        return activeOnly ? active(query) : query;
    }

    public static function exists(key:String, activeOnly:Bool = true):Bool {
        if (!validKey(key)) {
            return false;
        }
        return ContentCache.remember("access", "role-exists",
            [key, activeOnly, ContentCache.revision("extensions")],
            () -> byKey(key, activeOnly).exists());
    }

    public static function find(key:String, activeOnly:Bool = true):Null<RoleRecord> {
        if (!validKey(key)) {
            return null;
        }
        return ContentCache.remember("access", "role",
            [key, activeOnly, ContentCache.revision("extensions")], () -> {
                var role = byKey(key, activeOnly).select(columns).first();
                return role == null ? null : cast role.toObject();
            });
    }

    public static function label(key:String):String {
        if (!validKey(key)) {
            return key;
        }
        return ContentCache.remember("access", "role-label",
            [key, ContentCache.revision("extensions")], () -> {
                var row = byKey(key, true).select(["name"]).first();
                return row == null ? key : row.name;
            });
    }

    public static function grants(key:String):Array<String> {
        var rows:Array<{capability:String}> = ContentCache.remember("access", "role-grants",
            [key, 129], () -> {
                return RoleGrant.query.select(["capability"])
                    .where("role_key", key)
                    .orderBy("capability")
                    .limit(129)
                    .get()
                    .map(model -> cast model.toObject());
            });
        if (rows.length > 128) {
            throw new Exception("A role exceeds its permission limit.");
        }
        return [for (row in rows) row.capability];
    }

    public static function can(role:String, capability:String):Bool {
        if (!exists(role)) {
            return false;
        }
        var allowed = grants(role);
        return allowed.contains("*") || allowed.contains(capability);
    }

    public static function assignable(query:QueryBuilder<Role>,
            actorGrants:Array<String>):QueryBuilder<Role> {
        if (!actorGrants.contains("*")) {
            var excessive = RoleGrant.query.select(["role_key"])
                .whereNotIn("capability", cast actorGrants);
            query.whereNotInQuery("key", excessive);
        }
        return query;
    }

    public static function canAssign(actorRole:String, targetRole:String):Bool {
        return canManageTarget(actorRole, targetRole, true);
    }

    public static function canManage(actorRole:String, targetRole:String):Bool {
        return canManageTarget(actorRole, targetRole, false);
    }

    static function canManageTarget(actorRole:String, targetRole:String, activeOnly:Bool):Bool {
        if (!validKey(targetRole) || !exists(actorRole)) {
            return false;
        }
        return assignable(byKey(targetRole, activeOnly), grants(actorRole)).exists();
    }

    public static function options(actorGrants:Array<String>,
            selected:Array<String> = null):Array<RoleRecord> {
        var rows:Array<RoleRecord> = ContentCache.remember("access", "role-options",
            [actorGrants, 20, ContentCache.revision("extensions")], () -> {
                return assignable(active(Role.query.select(columns)),
                    actorGrants).orderBy("name")
                    .orderBy("key")
                    .limit(20)
                    .get()
                    .map(model -> cast model.toObject());
            });
        var known = [for (row in rows) row.key];
        var missing = selected == null ? [] : [
            for (key in selected)
                if (validKey(key) && !known.contains(key)) key
        ];
        if (missing.length > 20) {
            throw new Exception("Role options require a bounded selection.");
        }
        if (missing.length > 0) {
            var additional:Array<RoleRecord> = Role.query.select(columns)
                .whereIn("key", cast missing)
                .limit(missing.length)
                .get()
                .map(model -> cast model.toObject());
            rows = rows.concat(additional);
        }
        return rows;
    }

    public static function page(search:String, cursor:Null<PageCursor>):QueryPage<RoleRecord> {
        return ContentCache.remember("access", "manage-roles",
            [search, Pagination.token(cursor), 20], () -> {
                var query = filtered(search);
                if (cursor != null) {
                    query.where("key", cursor.before ? "<" : ">", cursor.id);
                }
                var direction = cursor != null && cursor.before ? "DESC" : "ASC";
                var rows:Array<RoleRecord> = query.orderBy("key", direction)
                    .limit(21)
                    .get()
                    .map(model -> cast model.toObject());
                return Pagination.slice(rows, 20, cursor);
            });
    }

    static function filtered(search:String):QueryBuilder<Role> {
        var query = Role.query.select(columns);
        if (search != "") {
            var escaped = StringTools.replace(StringTools.replace(StringTools.replace(search, "!",
                "!!"), "%", "!%"), "_", "!_");
            var pattern = '%${escaped}%';
            query.where(matches -> matches.whereLike("name", pattern).orWhereLike("key", pattern));
        }
        return query;
    }

    public static function count(search:String):Int {
        return ContentCache.remember("access", "role-count", [search],
            () -> filtered(search).count());
    }

    public static function capabilities(search:String = "",
            selected:Array<String> = null):Array<CapabilityRecord> {
        var rows:Array<CapabilityRecord> = ContentCache.remember("access", "capability-options",
            [search, 30], () -> {
                var query = Capability.query.select(["key", "name", "group_name", "owner"]);
                if (search != "") {
                    var escaped = StringTools.replace(StringTools.replace(StringTools.replace(search,
                        "!", "!!"), "%", "!%"),
                        "_", "!_");
                    var pattern = '%${escaped}%';
                    query.where(matches -> matches.whereLike("name", pattern)
                        .orWhereLike("key", pattern));
                }
                return query.orderBy("group_name")
                    .orderBy("key")
                    .limit(30)
                    .get()
                    .map(model -> cast model.toObject());
            });
        var known = [for (row in rows) row.key];
        var missing = selected == null ? [] : [
            for (key in selected)
                if (key != "*" && !known.contains(key)) key
        ];
        if (missing.length > 128) {
            throw new Exception("A role can contain at most 128 capabilities.");
        }
        if (missing.length > 0) {
            var additional:Array<CapabilityRecord> = Capability.query.select(["key", "name", "group_name", "owner"])
                .whereIn("key", cast missing)
                .limit(missing.length)
                .get()
                .map(model -> cast model.toObject());
            rows = rows.concat(additional);
        }
        return rows;
    }

    public static function ensureCapability(key:String, name:String, group:String,
            owner:String = ""):Void {
        if (!~/^[a-z][a-z0-9_.:-]{0,79}$/.match(key)
            || name == ""
            || name.length > 120
            || group.length > 80) {
            throw new Exception("Provide a valid capability key and label.");
        }
        var existing = Capability.query.select(["key", "owner"]).where("key", key).limit(1).first();
        if (existing != null) {
            if (existing.owner != owner) {
                throw new Exception("This capability belongs to another owner.");
            }
            return;
        }
        Capability.query.insert(["key" => key, "name" => name, "group_name" => group, "owner" => owner]);
        ContentCache.changed("access");
    }

    public static function save(key:String, name:String, description:String, enabled:Bool,
            capabilities:Array<String>, creating:Bool = false):Void {
        if (!validKey(key)
            || name == ""
            || name.length > 100
            || description.length > 500
            || capabilities.length > 128) {
            throw new Exception("Check the role key, label and permission limits.");
        }
        ContentLocks.run("roles", () -> {
            var role = Role.query.where("key", key);
            var roleExists = role.exists();
            if (creating == roleExists) {
                throw new Exception("Choose an existing role or a new unique key.");
            }
            if (key == "owner" && (!enabled || capabilities.length != 1 || capabilities[0] != "*")) {
                throw new Exception("The owner role must retain all capabilities and remain enabled.");
            }
            if (key != "owner" && capabilities.contains("*")) {
                throw new Exception("Only the protected owner role can grant every capability.");
            }
            var requested:Array<String> = [];
            for (capability in capabilities) {
                if (!requested.contains(capability)) {
                    requested.push(capability);
                }
            }
            var named = [for (capability in requested) if (capability != "*") capability];
            if (named.length > 0
                && Capability.query.select(["key"])
                    .whereIn("key", cast named)
                    .count() != named.length) {
                throw new Exception("Choose registered capabilities for this role.");
            }
            DBStatic.transaction(() -> {
                var values:Map<String,
                    Dynamic> = ["name" => name, "description" => description, "enabled" => enabled ? 1 : 0];
                if (creating) {
                    values.set("key", key);
                    values.set("system", 0);
                    values.set("owner", "");
                    Role.query.insert(values);
                } else {
                    role.update(values);
                }
                RoleGrant.query.where("role_key", key).delete();
                for (capability in requested) {
                    RoleGrant.query.insert(["role_key" => key, "capability" => capability]);
                }
            });
            ContentCache.changed("access");
            return true;
        });
    }

    public static function remove(key:String):Void {
        ContentLocks.run("roles", () -> {
            var role = Role.query.where("key", key).where("system", "!=", 1).where("owner", "");
            if (!validKey(key) || !role.exists() || Admin.query.where("role", key).exists()) {
                throw new Exception("Only unused site-owned custom roles can be removed.");
            }
            DBStatic.transaction(() -> {
                RoleGrant.query.where("role_key", key).delete();
                role.delete();
            });
            ContentCache.changed("access");
            return true;
        });
    }
}
