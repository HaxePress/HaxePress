package hx.press.database;

import hx.press.i18n.Languages;
import hx.well.facades.Schema;

class InitialSchema {
    public static function up():Void {
        if (!Schema.hasTable("categories"))
            Schema.create("categories", table -> {
                table.id();
                table.string("name").unique();
                table.string("name_key").unique();
                table.timestamps();
            });
        if (!Schema.hasTable("admins"))
            Schema.create("admins", table -> {
                table.id();
                table.string("email").unique();
                table.string("password");
                table.string("name").defaultValue("Editor");
                table.string("ui_language", 35).defaultValue("");
                table.dateTime("created_at");
            });
        if (!Schema.hasTable("content_items"))
            Schema.create("content_items", table -> {
                table.id();
                table.string("title");
                table.string("slug").unique();
                table.text("excerpt");
                table.text("content");
                table.string("category");
                table.string("image").defaultValue("");
                table.string("image_alt").defaultValue("");
                table.string("status").defaultValue("draft");
                table.integer("featured").defaultValue(0);
                table.integer("reading_minutes").defaultValue(0);
                // The language of the item, and the group of its translations: "" until it has one.
                table.string("language", 35).defaultValue(Languages.configuredDefault());
                table.string("translation_group", 24).defaultValue("");
                // Shown in languages that have no translation of it.
                table.integer("all_languages").defaultValue(0);
                table.dateTime("published_at").nullable();
                table.timestamps();
                table.index(["status", "published_at"]);
            });
        if (!Schema.hasTable("settings"))
            Schema.create("settings", table -> {
                table.string("key").primary();
                table.text("value");
            });
        if (!Schema.hasTable("login_attempts"))
            Schema.create("login_attempts", table -> {
                table.string("key").primary();
                table.integer("attempts").defaultValue(0);
                table.double("expires_at");
            });
    }
}
