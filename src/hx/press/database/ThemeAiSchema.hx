package hx.press.database;

import hx.well.facades.Schema;

class ThemeAiSchema {
    public static function up():Void {
        if (!Schema.hasTable("theme_ai_permissions")) {
            Schema.create("theme_ai_permissions", table -> {
                table.string("id", 32).primary();
                table.string("theme_id", 80);
                table.bigInteger("admin_id").unsigned();
                table.integer("allow_read").defaultValue(1);
                table.integer("allow_edit").defaultValue(1);
                table.integer("allow_media").defaultValue(1);
                table.unique(["theme_id", "admin_id"]);
                table.foreign("theme_id").references("id").on("theme_designs").cascadeOnDelete();
                table.foreign("admin_id").references("id").on("admins").cascadeOnDelete();
            });
        }
        if (!Schema.hasTable("theme_ai_connections")) {
            Schema.create("theme_ai_connections", table -> {
                table.string("id", 32).primary();
                table.string("theme_id", 80);
                table.bigInteger("admin_id").unsigned();
                table.string("token_hash", 64).unique();
                table.string("auth_version", 64);
                table.double("expires_epoch");
                table.unique(["theme_id", "admin_id"]);
                table.index(["theme_id", "expires_epoch"]);
                table.foreign("theme_id").references("id").on("theme_designs").cascadeOnDelete();
                table.foreign("admin_id").references("id").on("admins").cascadeOnDelete();
            });
        }
    }
}
