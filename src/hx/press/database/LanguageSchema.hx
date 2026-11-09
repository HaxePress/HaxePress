package hx.press.database;

import hx.well.facades.Schema;

class LanguageSchema {
    public static function up():Void {
        if (!Schema.hasTable("languages")) {
            Schema.create("languages", table -> {
                table.string("code", 35).primary();
                table.string("name", 60);
                table.string("direction", 3).defaultValue("ltr");
                table.integer("position").defaultValue(0);
                table.integer("is_default").defaultValue(0);
                table.integer("enabled").defaultValue(1);
                table.bigInteger("home_page_id").defaultValue(0);
                table.double("updated_epoch").defaultValue(0);
                table.index(["position", "code"]);
            });
        }
    }
}
