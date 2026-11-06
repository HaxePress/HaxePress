package hx.press.database;

import hx.press.ContentCache;
import hx.press.model.Capability;
import hx.press.model.Role;
import hx.press.model.RoleGrant;
import hx.well.facades.Schema;
import hx.well.facades.DBStatic;

class AccessSchema {
    public static function up():Void {
        if (!Schema.hasTable("capabilities")) {
            Schema.create("capabilities", table -> {
                table.string("key", 80).primary();
                table.string("name", 120);
                table.string("group_name", 80);
                table.string("owner").defaultValue("");
                table.index(["group_name", "key"]);
            });
        }
        if (!Schema.hasTable("roles")) {
            Schema.create("roles", table -> {
                table.string("key", 32).primary();
                table.string("name", 100);
                table.text("description");
                table.integer("enabled").defaultValue(1);
                table.integer("system").defaultValue(0);
                table.string("owner").defaultValue("");
                table.index(["enabled", "key"]);
            });
        }
        if (!Schema.hasTable("role_grants")) {
            Schema.create("role_grants", table -> {
                table.id();
                table.string("role_key", 32);
                table.string("capability", 80);
                table.unique(["role_key", "capability"]);
                table.index(["capability", "role_key"]);
                table.foreign("role_key").references("key").on("roles").cascadeOnDelete();
            });
        }
        var capabilities = [
            "content" => "Manage content",
            "publish" => "Publish content",
            "edit_others" => "Edit other authors' content",
            "taxonomy" => "Manage taxonomies",
            "media" => "Manage media",
            "navigation" => "Manage navigation",
            "activity" => "View activity",
            "extensions" => "Manage themes and plugins",
            "team" => "Manage team members",
            "roles" => "Manage roles and capabilities",
            "settings" => "Manage site settings",
            "subscribers" => "Manage subscribers",
            "account" => "Manage own account"
        ];
        for (key => name in capabilities) {
            if (!Capability.query.where("key", key).exists()) {
                Capability.query.insert(["key" => key, "name" => name, "group_name" => "CMS", "owner" => ""]);
            }
        }
        seed("owner", "Owner", ["*"]);
        seed("editor", "Editor", [
            "content",
            "publish",
            "edit_others",
            "taxonomy",
            "media",
            "navigation",
            "activity",
            "account"
        ]);
        seed("writer", "Writer", ["content", "media", "account"]);
    }

    static function seed(key:String, name:String, grants:Array<String>):Void {
        if (Role.query.where("key", key).exists()) {
            return;
        }
        DBStatic.transaction(() -> {
            Role.query.insert([
                "key" => key,
                "name" => name,
                "description" => "",
                "enabled" => 1,
                "system" => 1,
                "owner" => ""
            ]);
            for (capability in grants) {
                RoleGrant.query.insert(["role_key" => key, "capability" => capability]);
            }
        });
        ContentCache.changed("access");
    }
}
