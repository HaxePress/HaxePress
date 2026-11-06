package plugins;

import hx.press.ContentCache;
import hx.press.packages.PackageData;
import hx.press.packages.PackageData.PackageRecord;
import hx.press.packages.PackageManifest;
import hx.press.packages.SafePackageArchive;
import hx.press.plugins.PluginHealth;
import hx.press.plugins.PluginHost;
import hx.press.plugins.PluginModule;
import haxe.Exception;
import hx.well.config.ConfigData;
import hx.well.database.Connection;
import hx.well.facades.Environment;
import hx.well.facades.Storage;
import hx.press.model.InstalledPackage;
import hx.well.route.Route;
import hx.well.storage.StorageDisk;
import php.Global;

class PhpHost {
    static function check(value:Bool, message:String):Void {
        if (!value) {
            throw new Exception(message);
        }
    }

    static function load(disk:StorageDisk, path:String, entrypoint:String):PluginModule {
        return new PluginModule(disk.path(path), entrypoint);
    }

    static function install(disk:StorageDisk, filename:String, directory:String):PackageRecord {
        var target = 'installed/${directory}';
        var inspected = SafePackageArchive.extract(disk.getBytes(filename), target);
        var manifest = inspected.manifest;
        var id = 'plugin-${manifest.slug}';
        InstalledPackage.query.updateOrCreate(["id" => id], [
            "id" => id,
            "kind" => "plugin",
            "slug" => manifest.slug,
            "name" => manifest.name,
            "description" => manifest.description,
            "author" => manifest.author,
            "name_key" => manifest.name.toLowerCase(),
            "version" => manifest.version,
            "directory" => directory,
            "manifest" => Storage.disk("extensions").get('${target}/cms-package.json'),
            "settings" => "{}",
            "enabled" => 1,
            "setting_count" => manifest.fields.length,
            "last_error" => "",
            "installed_at" => "2026-11-04",
            "updated_at" => "2026-11-04"
        ]);
        ContentCache.changed("extensions");
        return PackageData.one(id);
    }

    static function lifecycle(record:PackageRecord, setting:String, phase:String):Void {
        PluginHealth.beginBoot();
        var disk = Storage.disk("extensions");
        var module = load(disk, 'installed/${record.directory}/php/module.json',
            "extensions.lifecycle.LifecyclePlugin");
        var settings:Dynamic = {};
        Reflect.setField(settings, setting, "true");
        var failed = false;
        var owned = [];
        try {
            owned = Route.batch(() -> module.create(new PhpTestPluginHost(), {settings: settings}));
            Route.batch(() -> module.destroy());
        } catch (error:Dynamic) {
            failed = Std.string(error).indexOf('Requested ${phase} failure') >= 0;
            PluginHealth.failed(record.id, record.directory, phase, error);
        }
        Route.batch(() -> {
            for (route in owned) {
                Route.unregister(route);
            }
        });
        module.close();
        var current = PackageData.one(record.id);
        check(failed
            && PluginHealth.restartRequired
            && current.restart_required == 1
            && current.enabled == 0,
            'PHP ${phase} warning state');
        check(Route.routes.length == 0, "PHP lifecycle failure left owned routes registered");
    }

    public static function main():Void {
        Environment.load(".env");
        check(Environment.env("APP_NAME") == "haxepress_test",
            "An isolated test environment is required");
        // PHP uses native serialization; the JVM fixture process has a separate cache.
        Environment.set("CACHE_PATH", "storage/php-cache");
        ConfigData.init();
        NativeApiChecks.run();
        Connection.create("default", {path: Environment.env("DB_PATH")});
        var arguments = Sys.args();
        var packages = Storage.build({
            driver: "local",
            root: arguments[0],
            read_only: true,
            throw_errors: true
        });
        var work = Storage.build({driver: "local", root: Sys.getCwd(), throw_errors: true});
        check(PackageManifest.serverTarget() == "php", "PHP runtime selection");
        var inspected = SafePackageArchive.extract(packages.getBytes("reading-companion-2.16.0.zip"),
            "reading", work);
        SafePackageArchive.extract(work.getBytes("inspection-only.zip"), "inspection-only", work);
        SafePackageArchive.extract(work.getBytes("streamed.zip"), "streamed", work);
        for (name in ["missing-php", "traversal", "checksum", "entry-limit"]) {
            var rejected = false;
            var destination = 'rejected-${name}';
            try {
                SafePackageArchive.extract(work.getBytes('${name}.zip'), destination, work);
            } catch (error:Dynamic) {
                rejected = true;
            }
            check(rejected && !work.exists(destination), 'PHP ZIP validation: ${name}');
        }
        check(PackageManifest.serverArtifact(inspected.manifest) == "php/module.json",
            "PHP selected another target's artifact");
        var host = new PhpTestPluginHost();
        var original = load(work, '${inspected.root}/php/module.json',
            inspected.manifest.entrypoint);
        var context = {
            settings: {message: "PHP reading note", content_note: "true", minimum_characters: "50"},
            data: {content: "Original", document: {status: "published", content: "Short"}}
        };
        original.create(host, context);
        check(original.dispatch("site.shared", context).blocks[0].content == "PHP reading note",
            "PHP hook dispatch");
        check(original.dispatch("content.render", context)
            .content == "Original\n\n---\n\nPHP reading note",
            "PHP content transformation");
        check(original.dispatch("content.saving", context).error != null, "PHP validation hook");
        var replacement = load(work, "updated/php/module.json", inspected.manifest.entrypoint);
        replacement.create(host, context);
        check(replacement.dispatch("site.shared", context)
            .blocks[0].content == "Updated module: PHP reading note",
            "PHP replacement did not execute its new classes");
        check(original.dispatch("site.shared", context).blocks[0].content == "PHP reading note",
            "PHP replacement changed the old instance");
        original.destroy();
        replacement.destroy();
        var before = Global.count(Global.spl_autoload_functions());
        original.close();
        replacement.close();
        check(Global.count(Global.spl_autoload_functions()) == before - 2, "PHP autoload cleanup");
        var closed = false;
        try {
            original.dispatch("site.shared", context);
        } catch (error:Dynamic) {
            closed = true;
        }
        check(closed, "A closed PHP module remained callable");
        var invalid = false;
        try {
            load(work, "invalid/php/module.json", "invalid.InvalidPlugin");
        } catch (error:Dynamic) {
            invalid = Std.string(error).indexOf("does not implement the CMS plugin API") >= 0;
        }
        check(invalid, "An incompatible PHP interface was accepted");
        check(Global.count(Global.spl_autoload_functions()) == before - 2,
            "A failed PHP load leaked its autoloader");
        var feedRecord = install(packages, "rss-2.16.0.zip", "php-rss");
        var extensions = Storage.disk("extensions");
        var feed = load(extensions, "installed/php-rss/php/module.json",
            "extensions.rss.RssPlugin");
        Route.batch(() -> feed.create(host, {settings: {}, packageInfo: {id: feedRecord.id}}));
        var feedRoute = Route.routes.filter(route -> route.value == "/rss.xml")[0];
        check(feedRoute != null, "PHP creation did not register the RSS route");
        var response = feedRoute.getHandler().execute(null).toResponse();
        check(response.toString().indexOf("PHP feed content item") >= 0,
            "PHP RSS ORM query/render");
        var cachedResponse = feedRoute.getHandler().execute(null).toResponse();
        check(cachedResponse.toString() == response.toString(), "PHP cached ORM record round trip");
        Route.batch(() -> feed.destroy());
        feed.close();
        check(Route.routes.length == 0, "PHP destruction did not remove the RSS route");
        var newsletter = install(packages, "newsletter-2.16.0.zip", "php-newsletter");
        var subscriptions = load(extensions, "installed/php-newsletter/php/module.json",
            "extensions.newsletter.NewsletterPlugin");
        Route.batch(() -> subscriptions.create(host,
            {settings: {title: "PHP newsletter"}, packageInfo: {id: newsletter.id}}));
        var navigation = subscriptions.dispatch("ui.navigation", {data: {location: "header"}});
        check(navigation.items[0].label == "Abone ol", "PHP package translation namespace");
        check(Route.routes.filter(route -> route.value == "/subscribe").length == 1,
            "PHP public newsletter route");
        var subscribeRoute = Route.routes.filter(route -> route.value == "/subscribe")[0];
        PluginValidationChecks.run(subscribeRoute.getHandler());
        check(Route.routes.filter(route -> route.value == "/admin/subscribers").length == 1,
            "PHP admin route group");
        Route.batch(() -> subscriptions.destroy());
        subscriptions.close();
        var lifecycleRecord = install(work, "lifecycle-test-2.16.0.zip", "php-lifecycle");
        lifecycle(lifecycleRecord, "fail_create", "creation");
        lifecycle(lifecycleRecord, "fail_destroy", "destruction");
        PluginDatabaseChecks.run(host, packages, work, "php-database");
        Connection.free();
        Sys.println("PASS Native PHP: target selection, hooks, validation, replacement, isolation and autoload cleanup");
        Sys.println("PASS PHP ZIP inspection: no code execution, target compatibility, paths, checksums, entry limits and data descriptors");
        Sys.println("PASS Native PHP RSS/newsletter: routes, ORM, translations and admin groups");
        Sys.println("PASS Native PHP lifecycle: creation/destruction warnings and managed route cleanup");
    }
}

class PhpTestPluginHost implements PluginHost {
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
