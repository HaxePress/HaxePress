package hx.press.database;

import hx.well.facades.Schema;

class ThemeDesignSchema {
    public static function up():Void {
        if (!Schema.hasTable("theme_designs")) {
            Schema.create("theme_designs", table -> {
                table.string("id", 80).primary();
                table.text("draft");
                table.text("published");
                table.integer("version").defaultValue(1);
                table.integer("published_version").defaultValue(0);
                table.dateTime("updated_at");
            });
        }
    }
}
