package hx.press.plugins;

import hx.press.SiteSettingsStore;
import hx.press.database.PluginSchema;
import haxe.Exception;
import haxe.Json;
import haxe.crypto.Md5;
import haxe.io.Bytes;
import hx.well.database.Connection;
import hx.well.database.schema.SchemaBuilder;
import hx.well.database.query.QueryBuilder;
import hx.well.facades.DBStatic;
import hx.well.model.BaseModelQuery;
import hx.press.model.PluginMigrationRecord;
import hx.press.model.PluginValue;
import hx.well.thread.MutexPool;
import hx.press.media.MediaDependencies;
import hx.press.media.MediaDependencyMode;
import hx.press.media.MediaLocks;

/** Plugin identity and persistence helpers; models and schema operations remain native HxWell. */
class PluginDatabase {
    public static inline var MAX_MIGRATIONS = 128;
    public static inline var MAX_VALUE_BYTES = 65535;
    static final locks = new MutexPool();

    public final slug:String;
    public final connection:String;

    public function new(slug:String, connection:String = "default") {
        validateSlug(slug);
        if (Connection.driver(connection) == null) {
            throw new Exception("Choose a configured database connection for this plugin.");
        }
        this.slug = slug;
        this.connection = connection;
    }

    static function validateSlug(slug:String):Void {
        if (slug == null || slug.length > 64 || !~/^[a-z0-9]+(-[a-z0-9]+)*$/.match(slug)) {
            throw new Exception("Plugin database namespaces require a valid package slug.");
        }
    }

    public static function prefix(slug:String):String {
        validateSlug(slug);
        var namespace = StringTools.replace(slug, "-", "_");
        if (namespace.length > 24) {
            namespace = namespace.substr(0, 15) + "_" + Md5.encode(slug).substr(0, 8);
        }
        return "plugin_" + namespace + "_";
    }

    public static function table(slug:String, name:String):String {
        if (name == null || !~/^[a-z][a-z0-9_]{0,31}$/.match(name)) {
            throw new Exception("Plugin table names must contain at most 32 lowercase letters, digits or underscores.");
        }
        return prefix(slug) + name;
    }

    public function tableName(name:String):String {
        return table(slug, name);
    }

    public function schema():SchemaBuilder {
        return new SchemaBuilder(connection);
    }

    /** Call once at startup when using a connection other than the application's default. */
    public function initialize():Void {
        var lock = connection + ":plugin-schema";
        locks.acquire(lock);
        try {
            PluginSchema.up(connection);
            locks.release(lock);
        } catch (error:Dynamic) {
            locks.release(lock);
            throw error;
        }
        if (connection != "default") {
            var model = new PluginValue();
            model.setConnection(connection);
            MediaDependencies.forPlugin(slug)
                .watch("values-" + Md5.encode(connection), model, "value",
                    MediaDependencyMode.Text, "Plugin data");
        }
    }

    function migrationQuery():BaseModelQuery<PluginMigrationRecord> {
        var model = new PluginMigrationRecord();
        model.setConnection(connection);
        return new BaseModelQuery(model);
    }

    function valueQuery():BaseModelQuery<PluginValue> {
        var model = new PluginValue();
        model.setConnection(connection);
        return new BaseModelQuery(model);
    }

    public function migrate(migrations:Array<PluginMigration>):Void {
        if (migrations == null || migrations.length > MAX_MIGRATIONS) {
            throw new Exception("A plugin can declare at most 128 migrations.");
        }
        var names:Array<String> = [];
        for (migration in migrations) {
            if (migration == null
                || migration.up == null
                || migration.name == null
                || !~/^[a-z0-9][a-z0-9_-]{0,127}$/.match(migration.name)
                || names.contains(migration.name)) {
                throw new Exception("Declare unique, stable names for every plugin migration.");
            }
            names.push(migration.name);
        }
        initialize();
        if (migrations.length == 0) {
            return;
        }
        var lock = connection + ":plugin-migrations:" + slug;
        locks.acquire(lock);
        try {
            var applied:Map<String, Bool> = [];
            var records = migrationQuery().select(["name"])
                .where("plugin_id", slug)
                .whereIn("name", names)
                .limit(MAX_MIGRATIONS)
                .get();
            for (record in records) {
                applied.set(Std.string(record.name), true);
            }
            for (migration in migrations) {
                if (applied.exists(migration.name)) {
                    continue;
                }
                var apply = () -> {
                    migration.up();
                    migrationQuery().create([
                        "id" => slug + ":" + migration.name,
                        "plugin_id" => slug,
                        "name" => migration.name,
                        "applied_at" => SiteSettingsStore.timestamp()
                    ]);
                };
                if (migration.transactional) {
                    DBStatic.connection(connection).transaction(apply);
                } else {
                    apply();
                }
            }
            locks.release(lock);
        } catch (error:Dynamic) {
            locks.release(lock);
            throw error;
        }
    }

    static function validateKey(key:String, scope:String):Void {
        if (key == null || key == "" || scope == null || Bytes.ofString(key).length > 128
            || Bytes.ofString(scope).length > 128 || ~/[\x00-\x1f\x7f]/.match(key)
            || ~/[\x00-\x1f\x7f]/.match(scope)) {
            throw new Exception("Plugin value keys and scopes must be bounded text without control characters.");
        }
    }

    function valueLookup(key:String, scope:String):QueryBuilder<PluginValue> {
        validateKey(key, scope);
        return valueQuery().where("plugin_id", slug).where("scope", scope).where("key", key);
    }

    public function get(key:String, fallback:Dynamic = null, scope:String = ""):Dynamic {
        var record = valueLookup(key, scope).select(["value"]).first();
        return record == null ? fallback : Json.parse(record.value);
    }

    public function put(key:String, value:Dynamic, scope:String = ""):Void {
        validateKey(key, scope);
        var serialized = Json.stringify(value);
        if (Bytes.ofString(serialized).length > MAX_VALUE_BYTES) {
            throw new Exception("Plugin JSON values must be smaller than 64 KB. Use a model or Storage for larger data.");
        }
        var dependencies = MediaDependencies.forPlugin(slug);
        if (connection != "default") {
            var model = new PluginValue();
            model.setConnection(connection);
            dependencies.watch("values-" + Md5.encode(connection), model, "value",
                MediaDependencyMode.Text, "Plugin data");
        }
        var reference = "value-" + Md5.encode(Json.stringify([connection, scope, key]));
        dependencies.withValue(reference, value, () -> {
            valueQuery().upsert([
                "plugin_id" => slug,
                "scope" => scope,
                "key" => key,
                "value" => serialized,
                "updated_at" => SiteSettingsStore.timestamp()
            ], ["plugin_id", "scope", "key"], ["value", "updated_at"]);
            return true;
        }, "Plugin data");
    }

    public function has(key:String, scope:String = ""):Bool {
        return valueLookup(key, scope).exists();
    }

    public function forget(key:String, scope:String = ""):Void {
        MediaLocks.run(() -> {
            valueLookup(key, scope).delete();
            var reference = "value-" + Md5.encode(Json.stringify([connection, scope, key]));
            MediaDependencies.forPlugin(slug).forget(reference);
            return true;
        });
    }
}
