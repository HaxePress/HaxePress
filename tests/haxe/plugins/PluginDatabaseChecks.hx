package plugins;

import hx.press.packages.PackageManifest;
import hx.press.packages.SafePackageArchive;
import hx.press.plugins.PluginDatabase;
import hx.press.plugins.PluginHost;
import hx.press.plugins.PluginMigration;
import hx.press.plugins.PluginModule;
import haxe.Exception;
import haxe.crypto.Md5;
import hx.well.database.Connection;
import hx.well.facades.Storage;
import hx.well.model.BaseModelQuery;
import hx.press.model.PluginMigrationRecord;
import hx.press.model.PluginValue;
import hx.press.model.MediaDependencySource;
import hx.well.storage.StorageDisk;

/** Runs against actual JVM, CPPIA and PHP modules and their native model constructors. */
class PluginDatabaseChecks {
    static function check(condition:Bool, message:String):Void {
        if (!condition) {
            throw new Exception(message);
        }
    }

    static function rejects(callback:Void->Void, message:String):Void {
        var rejected = false;
        try {
            callback();
        } catch (error:Dynamic) {
            rejected = true;
        }
        check(rejected, message);
    }

    static function load(work:StorageDisk, root:String, artifact:String,
            entrypoint:String):PluginModule {
        return new PluginModule(work.path('${root}/${artifact}'), entrypoint);
    }

    public static function run(host:PluginHost, packages:StorageDisk, work:StorageDisk,
            destination:String):Void {
        var inspected = SafePackageArchive.extract(packages.getBytes("database-test-2.16.0.zip"),
            destination, work);
        var artifact = PackageManifest.serverArtifact(inspected.manifest);
        var module = load(work, inspected.root, artifact, inspected.manifest.entrypoint);
        module.create(host, {});
        var key = 'record-\'${destination}';
        var scope = 'content:${destination}';
        var context = {
            data: {
                action: "write",
                key: key,
                title: "A plugin-owned record",
                rating: 4,
                content_id: null,
                scope: scope,
                metadata: {
                    nested: {enabled: true},
                    tags: ["notes", "Türkçe"],
                    count: 2
                }
            }
        };
        var created = module.dispatch("site.shared", context);
        check(created.entry.title == "A plugin-owned record" && created.entry.rating == 4,
            "Plugin-owned model create/query/toObject");
        check(created.metadata.nested.enabled == true && created.metadata.tags[1] == "Türkçe",
            "Plugin JSON value round trip");
        var id:Int = created.entry.id;
        context.data.title = "Updated plugin record";
        context.data.rating = 5;
        var updated = module.dispatch("site.shared", context);
        check(updated.entry.id == id && updated.entry.title == "Updated plugin record"
            && updated.entry.rating == 5,
            "Plugin-owned model update");
        module.destroy();
        module.close();
        module = load(work, inspected.root, artifact, inspected.manifest.entrypoint);
        module.create(host, {});
        context.data.action = "read";
        var reopened = module.dispatch("site.shared", context);
        check(reopened.entry.id == id && reopened.metadata.count == 2,
            "Plugin records survived module teardown/recreation");
        context.data.action = "forget";
        var forgotten = module.dispatch("site.shared", context);
        check(!forgotten.hasMetadata && forgotten.metadata == null && forgotten.entry.id == id,
            "Deleting plugin metadata must retain the custom model row");
        module.destroy();
        module.close();

        var token = Md5.encode(destination).substr(0, 12);
        var database = new PluginDatabase('probe-${token}');
        database.initialize();
        var other = new PluginDatabase('other-${token}');
        database.put("value", {number: 7}, "content:1");
        database.put("value", false, "content:2");
        database.put("empty", null);
        check(database.get("value", null, "content:1").number == 7,
            "Plugin value lookup must include its scope");
        check(database.get("value", true, "content:2") == false, "False must not use the fallback");
        check(database.has("empty") && database.get("empty", "missing") == null,
            "Stored null must differ from a missing key");
        check(other.get("value", "missing", "content:1") == "missing",
            "Plugin namespace isolation");
        var before = PluginValue.query.select(["id"])
            .where("plugin_id", database.slug)
            .where("scope", "content:1")
            .where("key", "value")
            .limit(1)
            .first();
        database.put("value", {number: 9}, "content:1");
        var after = PluginValue.query.select(["id"])
            .where("plugin_id", database.slug)
            .where("scope", "content:1")
            .where("key", "value")
            .limit(1)
            .first();
        check(before.id == after.id && database.get("value", null, "content:1").number == 9,
            "Atomic upsert must preserve the existing row identity");
        rejects(() -> database.put("large", StringTools.lpad("", "x", 65536)),
            "Oversized plugin JSON was accepted");
        rejects(() -> database.put("bad\nkey", 1), "Control characters were accepted in a key");
        rejects(() -> PluginDatabase.table("bad_slug", "entries"), "Invalid plugin namespace");
        rejects(() -> PluginDatabase.table("valid-slug", "../entries"), "Unsafe table suffix");
        check(PluginDatabase.table(StringTools.lpad("long", "a", 64),
            "abcdefghijklmnopqrstuvwxyzabcdef")
            .length <= 64,
            "Portable table identifier length");

        var calls = 0;
        var migrations = [new PluginMigration("001_once", () -> calls++)];
        database.migrate(migrations);
        database.migrate(migrations);
        check(calls == 1, "An applied migration ran more than once");
        rejects(() -> database.migrate([
            new PluginMigration("002_duplicate", () -> calls++),
            new PluginMigration("002_duplicate", () -> calls++)
        ]), "Duplicate migration names were accepted");
        check(calls == 1, "An invalid migration list produced side effects");
        rejects(() -> database.migrate([new PluginMigration("003_retry",
            () -> throw new Exception("Migration failure"))]),
            "Migration exceptions were swallowed");
        check(!PluginMigrationRecord.query.where("id", '${database.slug}:003_retry').exists(),
            "A failed migration was marked as applied");
        database.migrate([new PluginMigration("003_retry", () -> database.put("retry", true))]);
        check(database.get("retry") == true, "Failed migration retry");
        rejects(() -> database.migrate([
            new PluginMigration("004_atomic", () -> {
                database.put("rolled-back", true);
                throw new Exception("Atomic migration failure");
            }, true)
        ]), "Atomic migration failure was swallowed");
        check(!database.has("rolled-back")
            && !PluginMigrationRecord.query.where("id", '${database.slug}:004_atomic').exists(),
            "Migration data and ledger must roll back together");

        var local = Storage.disk("local");
        local.makeDirectory("");
        var alias = 'plugin-probe-${token}';
        Connection.create(alias, {path: local.path('${alias}.sqlite')});
        var alternate = new PluginDatabase(database.slug, alias);
        alternate.initialize();
        alternate.put("connection", "alternate");
        database.put("connection", "default");
        check(alternate.get("connection") == "alternate" && database.get("connection") == "default",
            "Configured connection isolation");
        var model = new PluginValue();
        model.setConnection(alias);
        var query = new BaseModelQuery<PluginValue>(model);
        var record = query.where("plugin_id", database.slug)
            .where("scope", "")
            .where("key", "connection")
            .limit(1)
            .first();
        check(record.__connection == alias, "Hydrated models lost their connection metadata");
        record.update(["value" => '"updated on alternate"']);
        check(alternate.get("connection") == "updated on alternate"
            && database.get("connection") == "default",
            "Model update used another connection");
        // The alias exists only in this fixture process, not the isolated HTTP server.
        alternate.forget("connection");
        MediaDependencySource.query.where("owner", 'plugin-${database.slug}')
            .where("connection_name", alias)
            .delete();
        BuiltInThemeChecks.run();
        MediaDependencyChecks.run(token);
        ContentStructureChecks.run(token);
        Sys.println("PASS Plugin database: native models, migrations/retry/rollback, scoped JSON, atomic upsert, connection isolation and persistence");
    }
}
