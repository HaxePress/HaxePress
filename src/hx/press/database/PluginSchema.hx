package hx.press.database;

import hx.well.facades.Schema;

class PluginSchema {
    public static function up(connection:String = "default"):Void {
        var schema = Schema.connection(connection);
        if (!schema.hasTable("plugin_migrations")) {
            schema.create("plugin_migrations", table -> {
                table.string("id", 200).primary();
                table.string("plugin_id", 64);
                table.string("name", 128);
                table.dateTime("applied_at");
                table.unique(["plugin_id", "name"]);
            });
        }
        if (!schema.hasTable("plugin_values")) {
            schema.create("plugin_values", table -> {
                table.id();
                table.string("plugin_id", 64);
                table.string("scope", 128).defaultValue("");
                table.string("key", 128);
                table.text("value");
                table.dateTime("updated_at");
                table.unique(["plugin_id", "scope", "key"]);
            });
        }
    }
}
