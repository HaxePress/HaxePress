package hx.press.database;

import hx.well.facades.Schema;

class MediaDependencySchema {
    public static function up():Void {
        if (!Schema.hasTable("media_dependencies")) {
            Schema.create("media_dependencies", table -> {
                table.id();
                table.bigInteger("media_id").unsigned();
                table.string("owner", 80);
                table.string("reference_key", 200);
                table.string("label", 240).defaultValue("");
                table.unique(["media_id", "owner", "reference_key"]);
                table.index(["owner", "reference_key", "media_id"]);
                table.foreign("media_id").references("id").on("media_assets").restrictOnDelete();
            });
        }
        if (!Schema.hasTable("media_dependency_sources")) {
            Schema.create("media_dependency_sources", table -> {
                table.string("key", 32).primary();
                table.string("owner", 80);
                table.string("connection_name", 80);
                table.string("table_name", 64);
                table.string("column_name", 64);
                table.string("mode", 12);
                table.string("label", 240).defaultValue("");
                table.index(["owner", "key"]);
            });
        }
    }
}
