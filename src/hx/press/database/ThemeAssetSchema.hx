package hx.press.database;

import hx.well.facades.Schema;

class ThemeAssetSchema {
    public static function up():Void {
        if (Schema.hasTable("theme_assets")) {
            return;
        }
        Schema.create("theme_assets", table -> {
            table.id();
            table.string("theme_id", 80);
            table.string("filename", 40);
            table.string("title", 180).defaultValue("");
            table.string("alt", 500).defaultValue("");
            table.string("mime_type", 80);
            table.integer("width");
            table.integer("height");
            table.integer("size");
            table.string("sha256", 64);
            table.timestamp("created_at");
            table.unique(["theme_id", "filename"]);
            table.index(["theme_id", "id"]);
            table.foreign("theme_id").references("id").on("theme_designs").cascadeOnDelete();
        });
    }
}
