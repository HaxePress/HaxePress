package fixtures;

import haxe.Exception;
import haxe.Json;
import haxe.Log;
import haxe.ds.StringMap;
import haxe.io.Bytes;
import haxe.io.Eof;
import hx.well.database.Connection;
import hx.well.database.query.QueryBuilder;
import hx.well.facades.Environment;
import hx.well.facades.Storage;
import hx.well.facades.Schema;
import hx.well.facades.DBStatic;
import hx.well.model.BaseModel;
import hx.well.model.BaseModelQuery;
import hx.press.model.Category;
import hx.press.model.ContentItem;
import hx.press.model.Setting;
import hx.press.model.Subscriber;
import hx.press.model.Tag;
import hx.press.model.ContentTag;
import hx.press.model.InstalledPackage;
import hx.press.model.ScheduledJob;
import hx.press.model.ScheduledBackup;
import hx.press.model.ThemeDesign;
import hx.press.model.ThemeAsset;
import hx.press.model.ThemeAiConnection;
import hx.press.model.ThemeAiPermission;
import hx.press.database.ThemeDesignSchema;
import hx.press.model.PackageHook;
import hx.press.model.PackageUpload;
import hx.press.model.ContentRevision;
import hx.press.model.EditorDraft;
import hx.press.model.MediaAsset;
import hx.press.media.ImageUploads;
import hx.press.model.ImageUpload;
import hx.press.model.MediaDependency;
import hx.press.model.MediaDependencySource;
import hx.press.model.Admin;
import hx.press.model.LoginAttempt;
import hx.press.model.MenuLink;
import hx.press.model.ActivityLog;
import java.NativeArray;
import sys.db.Sqlite;
import hx.press.packages.SafePackageArchive;
import haxe.crypto.Base64;
import hx.well.internal.SecureToken;
import hx.press.plugins.PluginModule;
import hx.press.packages.PackageManifest;
import hx.press.database.InitialSchema;
import hx.press.database.CmsSchema;
import hx.press.plugins.PluginHost;
import hx.well.route.Route;
import java.lang.Throwable;
import java.lang.System as JavaSystem;
import hx.well.config.ConfigData;
import hx.press.i18n.I18n;
import plugins.PluginDatabaseChecks;
import hx.press.model.PluginValue;
import hx.press.model.PluginMigrationRecord;
import hx.press.model.ContentType;
import hx.press.model.ContentTypePath;
import hx.press.model.ContentValue;
import hx.press.database.ContentStructureSchema;
import hx.press.database.AccessSchema;
import hx.press.config.DatabaseConfig;
import hx.press.navigation.NavigationRegions;
import hx.press.model.NavigationRegion;
import hx.press.model.Role;
import hx.press.model.RoleGrant;
import hx.press.model.Capability;
import plugins.NativeApiChecks;

/** A test-only JVM entry point for ORM fixtures over a private stdin/stdout pipe. */
@:keep
@:nativeGen
class FixtureProcess {
    public static function main(arguments:NativeArray<String>):Void {
        Log.trace = (_, ?position) -> {};
        Environment.load(".env");
        if (Environment.env("APP_NAME") != "haxepress_test") {
            throw new Exception("The fixture process requires an isolated integration-test database");
        }
        ConfigData.init();
        var database = DatabaseConfig.definitions().get("default");
        if (database.driver == "mysql") {
            Connection.create("default", {
                host: database.host,
                port: database.port,
                database: database.database,
                user: database.username,
                pass: database.password
            });
        } else {
            var path = database.path;
            Connection.create("default", {path: path},
                () -> new GuardedConnection(Sqlite.open(path)));
        }
        respond({ok: true, value: "ready"});

        while (true) {
            var line:String;
            try {
                line = Sys.stdin().readLine();
            } catch (error:Eof) {
                break;
            }
            try {
                var command:Dynamic = Json.parse(line);
                var value = handle(command);
                Connection.free();
                respond({ok: true, value: value});
            } catch (error:Dynamic) {
                Connection.free();
                var nativeError:Dynamic = (error is Exception) ? (cast error : Exception)
                    .native : error;
                if (Std.isOfType(nativeError, Throwable)) {
                    var throwable:Throwable = cast nativeError;
                    throwable.printStackTrace(JavaSystem.err);
                }
                respond({ok: false, error: Std.string(error)});
            }
        }
        Connection.free();
        Sys.exit(0);
    }

    static function respond(value:Dynamic):Void {
        Sys.println(Json.stringify(value));
    }

    static function handle(command:Dynamic):Dynamic {
        if (command.action == "backup_probe") {
            return backupProbe(command);
        }
        if (command.action == "native_api_checks") {
            NativeApiChecks.run();
            return true;
        }
        if (command.action == "translate") {
            ConfigData.init();
            var parameters:Map<String, Dynamic> = [];
            if (command.parameters != null) {
                for (name in Reflect.fields(command.parameters)) {
                    parameters.set(name, Reflect.field(command.parameters, name));
                }
            }
            return I18n.t(command.key, parameters, command.namespace, command.locale);
        }
        if (command.action == "initialize_schema") {
            ConfigData.init();
            InitialSchema.up();
            CmsSchema.up();
            AccessSchema.up();
            ContentStructureSchema.up();
            ThemeDesignSchema.up();
            NavigationRegions.initialize();
            return true;
        }
        if (command.action == "transaction_boundary") {
            try {
                DBStatic.transaction(() -> {
                    Setting.query.create(["key" => command.beforeKey, "value" => "before"]);
                    if (command.rollback == true) {
                        throw new ExpectedRollback();
                    }
                });
            } catch (error:ExpectedRollback) {}
            Setting.query.create(["key" => command.afterKey, "value" => "after"]);
            return true;
        }
        if (command.action == "inspect_package") {
            var destination = 'package-probes/${SecureToken.generate(32)}';
            return SafePackageArchive.extract(Base64.decode(command.archive), destination);
        }
        if (command.action == "plugin_database_checks") {
            var packages = Storage.build({
                driver: "local",
                root: command.packageRoot,
                read_only: true,
                throw_errors: true
            });
            PluginDatabaseChecks.run(new FixturePluginHost(), packages,
                Storage.disk("extensions"), 'database-probes/${SecureToken.generate(16)}');
            return true;
        }
        if (command.action == "dispatch_package") {
            var destination = 'package-probes/${SecureToken.generate(32)}';
            var packageData = SafePackageArchive.extract(Base64.decode(command.archive),
                destination);
            var artifact = PackageManifest.serverArtifact(packageData.manifest);
            var module = new PluginModule(Storage.disk("extensions")
                .path('${packageData.root}/${artifact}'),
                packageData.manifest.entrypoint);
            try {
                Route.batch(() -> module.create(new FixturePluginHost(), command.context));
                var response = module.dispatch(command.event, command.context);
                Route.batch(() -> module.destroy());
                module.close();
                return response;
            } catch (error:Dynamic) {
                module.close();
                throw error;
            }
        }
        if (command.action == "drop_categories") {
            Schema.drop("categories");
            return true;
        }
        if (command.action == "expire_image_uploads") {
            ImageUploads.expire();
            return true;
        }
        return switch (command.entity) {
            case "items": execute(ContentItem.query, command);
            case "content_types": execute(ContentType.query, command);
            case "content_type_paths": execute(ContentTypePath.query, command);
            case "content_values": execute(ContentValue.query, command);
            case "navigation_regions": execute(NavigationRegion.query, command);
            case "roles": execute(Role.query, command);
            case "role_grants": execute(RoleGrant.query, command);
            case "capabilities": execute(Capability.query, command);
            case "categories": execute(Category.query, command);
            case "subscribers": execute(Subscriber.query, command);
            case "settings": execute(Setting.query, command);
            case "tags": execute(Tag.query, command);
            case "content_tags": execute(ContentTag.query, command);
            case "cms_packages": execute(InstalledPackage.query, command);
            case "scheduled_jobs": execute(ScheduledJob.query, command);
            case "scheduled_backup_files": execute(ScheduledBackup.query, command);
            case "theme_designs": execute(ThemeDesign.query, command);
            case "theme_assets": execute(ThemeAsset.query, command);
            case "theme_ai_connections": execute(ThemeAiConnection.query, command);
            case "theme_ai_permissions": execute(ThemeAiPermission.query, command);
            case "package_hooks": execute(PackageHook.query, command);
            case "package_uploads": execute(PackageUpload.query, command);
            case "content_revisions": execute(ContentRevision.query, command);
            case "editor_drafts": execute(EditorDraft.query, command);
            case "media_dependencies": execute(MediaDependency.query, command);
            case "media_dependency_sources": execute(MediaDependencySource.query, command);
            case "media_assets": execute(MediaAsset.query, command);
            case "image_uploads": execute(ImageUpload.query, command);
            case "admins": execute(Admin.query, command);
            case "login_attempts": execute(LoginAttempt.query, command);
            case "menu_links": execute(MenuLink.query, command);
            case "activity_logs": execute(ActivityLog.query, command);
            case "plugin_values": execute(PluginValue.query, command);
            case "plugin_migrations": execute(PluginMigrationRecord.query, command);
            default: throw new Exception("Unknown fixture model");
        };
    }

    static function backupProbe(command:Dynamic):Dynamic {
        var tableName = "plugin_backup_probe";
        var model = new BaseModel<Dynamic>();
        model.setTable(tableName);
        switch (command.operation) {
            case "create":
                Schema.create(tableName, table -> {
                    table.string("bucket", 24);
                    table.integer("sequence");
                    table.bigInteger("content_id").unsigned();
                    table.bigInteger("precise");
                    table.binary("payload");
                    table.primary(["bucket", "sequence"]);
                    table.index(["content_id"]);
                    table.foreign("content_id")
                        .references("id")
                        .on("content_items")
                        .cascadeOnDelete();
                });
                for (index in 0...20) {
                    new QueryBuilder(model).insert([
                        "bucket" => index < 18 ? "a" : "b",
                        "sequence" => index,
                        "content_id" => command.contentId,
                        "precise" => "9007199254740993",
                        "payload" => Bytes.ofHex("00ffa97a")
                    ]);
                }
                return true;
            case "drop":
                Schema.dropIfExists(tableName);
                return true;
            case "verify":
                var rows = new QueryBuilder(model)
                    .selectWithText(["precise", "payload", "content_id"],
                        ["precise", "content_id"])
                    .limit(21)
                    .getResultSet();
                var count = 0;
                while (rows.hasNext()) {
                    var row = rows.next();
                    var payload:Bytes = row.payload;
                    if (row.precise != "9007199254740993"
                        || payload.toHex() != "00ffa97a"
                        || row.content_id != Std.string(command.contentId)) {
                        return false;
                    }
                    count++;
                }
                return count == 20;
            default:
                throw new Exception("Unknown backup probe operation.");
        }
    }

    static function execute<T:BaseModel<T>>(model:BaseModelQuery<T>, command:Dynamic):Dynamic {
        if (command.action == "create") {
            var inputs:Array<Dynamic> = command.records;
            if (inputs.length > 100) {
                throw new Exception("Fixture writes must use batches of at most 100 records");
            }
            var identifiers:Array<Dynamic> = [];
            for (input in inputs) {
                var record = model.create(attributes(input));
                identifiers.push(Reflect.field(record.toObject(), model.getPrimary()));
            }
            return identifiers;
        }

        var columns:Array<String> = command.columns == null ? [model.getPrimary()] : command.columns;
        var query = model.select(columns);
        var filters:Array<Dynamic> = command.filters == null ? [] : command.filters;
        for (filter in filters) {
            if (filter.op == "in") {
                query.whereIn(filter.column, filter.value);
            } else {
                query.where(filter.column, filter.op, filter.value);
            }
        }
        return switch (command.action) {
            case "count": query.count();
            case "update":
                query.update(attributes(command.values));
                true;
            case "delete":
                query.delete();
                true;
            case "rows":
                if (command.after != null) {
                    query.where(model.getPrimary(), ">", command.after);
                }
                var limit = command.limit == null ? 100 : Std.int(command.limit);
                if (limit < 1 || limit > 100) {
                    throw new Exception("Fixture reads must use batches of at most 100 records");
                }
                query.orderBy(model.getPrimary()).limit(limit);
                readRows(query);
            default: throw new Exception("Unknown fixture operation");
        };
    }

    static function attributes(input:Dynamic):StringMap<Dynamic> {
        var values = new StringMap<Dynamic>();
        for (field in Reflect.fields(input)) {
            values.set(field, Reflect.field(input, field));
        }
        return values;
    }

    static function readRows<T>(query:QueryBuilder<T>):Array<Dynamic> {
        var result = query.getResultSet();
        var fields = result.getFieldsNames();
        var rows:Array<Dynamic> = [];
        while (result.hasNext()) {
            var row = result.next();
            for (dateField in ["published_at", "created_at", "updated_at"]) {
                var index = fields.indexOf(dateField);
                if (index >= 0) {
                    Reflect.setField(row, dateField, result.getResult(index + 1));
                }
            }
            rows.push(row);
        }
        return rows;
    }
}

class FixturePluginHost implements PluginHost {
    public function new() {}

    public function admin(callback:Void->Void):Void {
        Route.path("/admin").group(callback);
    }

    public function can(capability:String):Bool {
        return true;
    }

    public function schedule(pluginId:String, key:String, intervalSeconds:Int,
            ?payload:String):Void {
        throw new Exception("Scheduling requires the application host.");
    }

    public function unschedule(pluginId:String, key:String):Bool {
        throw new Exception("Scheduling requires the application host.");
    }
}

private class ExpectedRollback extends Exception {
    public function new() {
        super("Requested fixture rollback");
    }
}
