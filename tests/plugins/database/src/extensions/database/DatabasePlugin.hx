package extensions.database;

import hx.press.SiteSettingsStore;
import hx.press.plugins.PluginDatabase;
import hx.press.plugins.PluginEntrypoint;
import hx.press.plugins.PluginHost;
import hx.press.plugins.PluginMigration;
import haxe.Json;

class DatabasePlugin implements PluginEntrypoint {
    static inline var SCHEMA_VERSION = 2;

    var database:PluginDatabase;

    public function new() {}

    public function onCreate(host:PluginHost, context:String):Void {
        database = new PluginDatabase("database-test");
        var schema = database.schema();
        var entries = database.tableName("entries");
        var migrations = [
            new PluginMigration("001_create_entries", () -> {
                if (!schema.hasTable(entries)) {
                    schema.create(entries, table -> {
                        table.id();
                        table.string("key").unique();
                        table.string("title");
                        table.integer("content_id").nullable();
                        table.dateTime("created_at");
                        table.foreign("content_id")
                            .references("id")
                            .on("content_items")
                            .cascadeOnDelete();
                    });
                }
            }),
            new PluginMigration("002_add_rating", () -> {
                if (!schema.hasColumn(entries, "rating")) {
                    schema.table(entries, table -> table.integer("rating").defaultValue(0));
                }
            })
        ];
        if (SCHEMA_VERSION >= 3) {
            migrations.push(new PluginMigration("003_add_reference", () -> {
                if (!schema.hasColumn(entries, "reference")) {
                    schema.table(entries, table -> table.string("reference").defaultValue(""));
                }
            }));
        }
        database.migrate(migrations);
    }

    public function onDestroy():Void {}

    public function dispatch(event:String, context:String):String {
        var input:Dynamic = Json.parse(context);
        var data:Dynamic = input.data;
        var scope:String = data.scope == null ? "" : data.scope;
        if (data.action == "write") {
            DatabaseEntry.query.updateOrCreate(["key" => data.key], [
                "title" => data.title,
                "rating" => data.rating,
                "content_id" => data.content_id,
                "created_at" => SiteSettingsStore.timestamp()
            ]);
            database.put("metadata", data.metadata, scope);
        }
        if (data.action == "forget") {
            database.forget("metadata", scope);
        }
        var entry = DatabaseEntry.query.select(["id", "key", "title", "rating", "content_id", "created_at"])
            .where("key", data.key)
            .limit(1)
            .first();
        return Json.stringify({
            entry: entry == null ? null : entry.toObject(),
            metadata: database.get("metadata", null, scope),
            hasMetadata: database.has("metadata", scope),
            hasUpgrade: database.schema().hasColumn(database.tableName("entries"), "reference")
        });
    }
}
