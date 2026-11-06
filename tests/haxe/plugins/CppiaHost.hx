package plugins;

import hx.press.plugins.PluginModule;
import hx.press.plugins.PluginHost;
import hx.press.SiteSettingsStore;
import hx.press.ContentCache;
import hx.press.Pagination;
import hx.well.route.Route;
import hx.well.database.Connection;
import hx.well.facades.Environment;
import hx.well.config.ConfigData;
import hx.press.model.Subscriber;
import hx.press.model.InstalledPackage;
import hx.press.model.Setting;
import hx.press.i18n.I18n;
import hx.press.packages.PackageManifest;
import hx.press.packages.SafePackageArchive;
import haxe.Exception;
import haxe.Json;
import haxe.io.Path;
import haxe.crypto.Base64;
import hx.well.facades.Storage;
import haxe.io.Bytes;

class CppiaHost {
    static function check(value:Bool, message:String):Void {
        if (!value) {
            throw new Exception(message);
        }
    }

    public static function main():Void {
        Sys.println("CPPIA test: host main");
        Environment.load(".env");
        ConfigData.init();
        NativeApiChecks.run();
        Connection.create("default", {path: Environment.env("DB_PATH")});
        check(I18n.t("Save content", null, "cms", "tr") == "İçeriği kaydet",
            "Native core catalogue");
        check(I18n.t("Content count", ["count" => 2], "cms", "en") == "2 content items",
            "Native plural catalogue");
        var arguments = Sys.args();
        var work = Storage.build({driver: "local", root: Sys.getCwd(), throw_errors: true});
        var archives = Storage.build({
            driver: "local",
            root: Path.directory(arguments[0]),
            read_only: true,
            throw_errors: true
        });
        var packages = Storage.build({
            driver: "local",
            root: Path.directory(arguments[5]),
            read_only: true,
            throw_errors: true
        });
        var output = Path.withoutDirectory(arguments[2]);
        check(PackageManifest.serverTarget() == "cpp", "C++ runtime selection");
        var inspected = SafePackageArchive.extract(archives.getBytes(Path.withoutDirectory(arguments[0])),
            '${output}/valid', work);
        var artifact = PackageManifest.serverArtifact(inspected.manifest);
        check(artifact == "server.cppia", "C++ selected a non-CPPIA artifact");
        var first = new PluginModule(work.path('${inspected.root}/${artifact}'),
            inspected.manifest.entrypoint);
        Sys.println("CPPIA test: module loaded");
        var host = new NativePluginHost();
        var context = {
            settings: {
                message: "A native reading note.",
                content_note: "true",
                minimum_characters: "50"
            },
            data: {
                content: "Original content",
                document: {
                    status: "published",
                    content: "Too short"
                }
            }
        };
        Route.batch(() -> first.create(host, context));
        var note = first.dispatch("site.shared", context);
        check(note.blocks[0].content == "A native reading note.", "CPPIA hook output");
        var rendered = first.dispatch("content.render", context);
        check(rendered.content == "Original content\n\n---\n\nA native reading note.",
            "CPPIA render hook");
        var rejected = first.dispatch("content.saving", context);
        check(rejected.error != null, "CPPIA validation hook");
        var replacement = new PluginModule(work.path(Path.withoutDirectory(arguments[1])),
            "example.reading.ReadingPlugin");
        Route.batch(() -> replacement.create(host, context));
        check(replacement.dispatch("site.shared", context)
            .blocks[0].content == "Updated module: A native reading note.",
            "CPPIA replacement");
        check(first.dispatch("site.shared", context).blocks[0].content == "A native reading note.",
            "CPPIA module isolation");
        first.destroy();
        replacement.destroy();
        first.close();
        replacement.close();
        var closed = false;
        try {
            first.dispatch("site.shared", context);
        } catch (error:Dynamic) {
            closed = true;
        }
        check(closed, "A closed module remained callable");
        var missing = false;
        try {
            new PluginModule(work.path(Path.withoutDirectory(arguments[1])),
                "example.reading.MissingPlugin");
        } catch (error:Dynamic) {
            missing = true;
        }
        check(missing, "A missing CPPIA entrypoint was accepted");
        var invalid = false;
        try {
            new PluginModule(work.path(Path.withoutDirectory(arguments[3])),
                "plugins.InvalidEntrypoint");
        } catch (error:Dynamic) {
            invalid = Std.string(error).indexOf("does not implement the CMS plugin API") >= 0;
        }
        check(invalid, "An incompatible CPPIA interface was accepted");
        check(Subscriber.query != null, "Native subscriber model metadata");
        Sys.println("CPPIA test: feature modules");
        var rss = SafePackageArchive.extract(packages.getBytes(Path.withoutDirectory(arguments[5])),
            '${output}/rss', work);
        var rssArtifact = PackageManifest.serverArtifact(rss.manifest);
        var feed = new PluginModule(work.path('${rss.root}/${rssArtifact}'),
            rss.manifest.entrypoint);
        Route.batch(() -> feed.create(host, {settings: {}, packageInfo: {id: "plugin-rss"}}));
        var feedRoute = Route.routes.filter(route -> route.value == "/rss.xml")[0];
        check(feedRoute != null, "CPPIA onCreate did not register the native RSS route");
        var response = feedRoute.getHandler().execute(null).toResponse();
        check(response.toString().indexOf("Native feed content item") >= 0,
            "CPPIA RSS route did not query/render content");
        Route.batch(() -> feed.destroy());
        check(!Route.routes.contains(feedRoute), "CPPIA onDestroy did not remove RSS");
        feed.close();
        var newsletterDirectory = 'native-newsletter-${Path.withoutDirectory(arguments[2])}';
        var newsletter = SafePackageArchive.extract(packages.getBytes(Path.withoutDirectory(arguments[6])),
            'installed/${newsletterDirectory}');
        InstalledPackage.query.updateOrCreate(["id" => "plugin-newsletter"], [
            "id" => "plugin-newsletter",
            "kind" => "plugin",
            "slug" => "newsletter",
            "name" => "Newsletter",
            "description" => newsletter.manifest.description,
            "author" => newsletter.manifest.author,
            "name_key" => "newsletter",
            "version" => "2.16.0",
            "directory" => newsletterDirectory,
            "manifest" => Storage.disk("extensions").get('${newsletter.root}/cms-package.json'),
            "settings" => "{}",
            "enabled" => 1,
            "setting_count" => 1,
            "last_error" => "",
            "installed_at" => "2026-11-04",
            "updated_at" => "2026-11-04"
        ]);
        ContentCache.changed("extensions");
        var newsletterArtifact = PackageManifest.serverArtifact(newsletter.manifest);
        var subscriptions = new PluginModule(Storage.disk("extensions")
            .path('${newsletter.root}/${newsletterArtifact}'),
            newsletter.manifest.entrypoint);
        Route.batch(() -> subscriptions.create(host,
            {settings: {title: "Native newsletter"}, packageInfo: {id: "plugin-newsletter"}}));
        Setting.query.updateOrCreate(["key" => "locale"], ["value" => "tr"]);
        ContentCache.settingsChanged();
        var navigation = subscriptions.dispatch("ui.navigation", {data: {location: "header"}});
        check(navigation.items[0].label == "Abone ol",
            "CPPIA module did not use its native translation namespace");
        check(Route.routes.filter(route -> route.value == "/subscribe").length == 1,
            "CPPIA newsletter public route");
        var subscribeRoute = Route.routes.filter(route -> route.value == "/subscribe")[0];
        PluginValidationChecks.run(subscribeRoute.getHandler());
        check(Route.routes.filter(route -> route.value == "/admin/subscribers").length == 1,
            "CPPIA newsletter admin route");
        Route.batch(() -> subscriptions.destroy());
        subscriptions.close();
        PluginDatabaseChecks.run(host, packages, work, '${output}/database');
        Connection.free();
        var cases:Array<Dynamic> = work.json(Path.withoutDirectory(arguments[4]));
        for (index in 0...cases.length) {
            var rejected = false;
            var destination = '${output}/rejected-${index}';
            try {
                SafePackageArchive.extract(Base64.decode(cases[index].archive), destination, work);
            } catch (error:Dynamic) {
                rejected = true;
            }
            check(rejected && !work.exists(destination),
                'CPPIA archive validation: ${cases[index].name}');
        }
        Sys.println("PASS Native C++/CPPIA: shared interface, hooks, validation, replacement, isolation and close");
        Sys.println("PASS C++ ZIP inspection: target selection, paths, duplicates, checksums and bounded streaming");
        Sys.println("PASS Native CPPIA RSS/newsletter: lifecycle, HxWell routes, ORM, XML and shared translations");
    }
}

class NativePluginHost implements PluginHost {
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
