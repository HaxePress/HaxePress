package hx.press.plugins;

import haxe.Exception;
import hx.press.validation.ValidationResponder;
import hx.well.template.StatusTemplate;
import hx.press.ContentCache;
import hx.well.database.Connection;
import hx.well.facades.Storage;
import hx.well.http.ResponseBuilder;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.handler.AbstractHandler;
import hx.well.route.RouteElement;
import hx.well.route.Route;
import hx.press.CmsVersion;
import hx.press.SiteSettingsStore;
import hx.press.i18n.I18n;
import hx.press.MediaStorage;
import hx.press.packages.PackageData;
import hx.press.packages.BuiltInPlugins;
import hx.press.packages.PackageManager;
import hx.press.packages.PackageData.PackageRecord;
import hx.press.packages.PackageManifest;
import hx.press.packages.PackageSettings;
import hx.press.packages.PackageStorage;
import hx.concurrent.collection.SynchronizedMap;
import hx.press.model.InstalledPackage;
import hx.well.thread.MutexPool;

typedef PluginAsset = {
    var id:String;
    var module:String;
    var stylesheet:String;
    var settings:Map<String, String>;
}

typedef PluginBlock = {
    var id:String;
    var slot:String;
    var content:String;
}

private class LivePlugin {
    public var module:PluginModule;
    public var routes:Array<RouteElement> = [];
    public var record:PackageRecord;

    public function new(record:PackageRecord, module:PluginModule) {
        this.record = record;
        this.module = module;
    }
}

class PluginRuntime {
    static final locks = new MutexPool();
    static final modules:SynchronizedMap<String, LivePlugin> = SynchronizedMap.newStringMap();
    public static var ready(default, null):Bool = false;

    static function key(record:PackageRecord):String {
        return '${record.id}:${record.directory}';
    }

    static function context(record:PackageRecord, data:Dynamic):Dynamic {
        var manifest = PackageManifest.parse(record.manifest);
        var configured = PackageSettings.values(manifest, record.settings, true);
        return {
            apiVersion: CmsVersion.pluginApiVersion,
            cmsVersion: CmsVersion.version,
            locale: I18n.locale(),
            packageInfo: {
                id: record.id,
                pluginId: record.plugin_id,
                slug: record.slug,
                version: record.version
            },
            database: {
                connection: "default",
                namespace: record.slug,
                tablePrefix: PluginDatabase.prefix(record.slug)
            },
            settings: configured,
            site: SiteSettingsStore.settings(),
            data: data
        };
    }

    public static function boot():Void {
        PluginHealth.beginBoot();
        ready = true;
        var after = "";
        while (true) {
            var batch = PackageData.enabledBatch(after);
            if (batch.length == 0) {
                break;
            }
            for (record in batch) {
                try {
                    start(record);
                } catch (error:Dynamic) {
                    trace('Plugin could not start: ${record.id}: ${Std.string(error)}');
                }
            }
            after = batch[batch.length - 1].id;
        }
    }

    public static function start(record:PackageRecord):Void {
        var manifest = PackageManifest.parse(record.manifest);
        try {
            PackageManifest.requireCompatible(manifest);
        } catch (error:Dynamic) {
            InstalledPackage.query.where("id", record.id)
                .update(["enabled" => 0, "last_error" => Std.string(error)]);
            ContentCache.changed("extensions");
            throw error;
        }
        if (!PackageManifest.hasServer(manifest)) {
            return;
        }
        var moduleKey = key(record);
        locks.acquire(moduleKey);
        if (modules.exists(moduleKey)) {
            locks.release(moduleKey);
            return;
        }
        var module:PluginModule = null;
        try {
            var artifact = PackageManifest.serverArtifact(manifest);
            var routes = Route.batch(() -> {
                var path = Storage.disk("extensions")
                    .path('${PackageStorage.installed(record.directory)}/${artifact}');
                module = new PluginModule(path, manifest.entrypoint);
                module.create(new DefaultPluginHost(record.plugin_id), context(record, {}));
            }, route -> {
                route.attribute("hx.press.plugin", record.id);
                var handler = route.getHandler();
                if (handler != null) {
                    route.handler(new PluginRouteHandler(record.id, record.directory, handler));
                }
            });
            var live = new LivePlugin(record, module);
            live.routes = routes;
            modules.set(moduleKey, live);
            locks.release(moduleKey);
        } catch (error:Dynamic) {
            if (module != null) {
                try {
                    Route.batch(() -> module.destroy());
                } catch (cleanup:Dynamic) {}
                try {
                    module.close();
                } catch (cleanup:Dynamic) {}
            }
            locks.release(moduleKey);
            PluginHealth.failed(record.id, record.directory, "creation", error);
            throw error;
        }
    }

    public static function stop(record:PackageRecord):Void {
        var moduleKey = key(record);
        locks.acquire(moduleKey);
        var live = modules.get(moduleKey);
        if (live == null) {
            locks.release(moduleKey);
            return;
        }
        var failure:Dynamic = null;
        try {
            Route.batch(() -> live.module.destroy());
        } catch (error:Dynamic) {
            failure = error;
        }
        Route.batch(() -> {
            for (route in live.routes) {
                Route.unregister(route);
            }
        });
        try {
            live.module.close();
        } catch (error:Dynamic) {
            if (failure == null) {
                failure = error;
            }
        }
        modules.remove(moduleKey);
        locks.release(moduleKey);
        if (failure != null) {
            PluginHealth.failed(record.id, record.directory, "destruction", failure);
            throw failure;
        }
    }

    public static function shutdown():Void {
        ready = false;
        var runningPlugins = modules.copy();
        for (live in runningPlugins) {
            try {
                stop(live.record);
            } catch (error:Dynamic) {
                trace('Plugin shutdown failed: ${Std.string(error)}');
            }
        }
        Connection.free();
    }

    static function withRoute<T>(id:String, directory:String, callback:Void->T, missing:Void->T):T {
        var moduleKey = '${id}:${directory}';
        // The backup module snapshots installed packages. Follow the lifecycle lock order.
        var packageSnapshot = id == BuiltInPlugins.BACKUP;
        if (packageSnapshot) {
            PackageManager.writes.acquire("packages");
        }
        locks.acquire(moduleKey);
        try {
            var active = directory != null && modules.exists(moduleKey)
                && PackageData.activeDirectory(id) == directory;
            var result = active ? callback() : missing();
            locks.release(moduleKey);
            if (packageSnapshot) {
                PackageManager.writes.release("packages");
            }
            return result;
        } catch (error:Dynamic) {
            locks.release(moduleKey);
            if (packageSnapshot) {
                PackageManager.writes.release("packages");
            }
            throw error;
        }
    }

    public static function runScheduled(record:PackageRecord, id:String, task:String,
            payload:Dynamic):Bool {
        return withRoute(record.id, record.directory, () -> {
            var live = modules.get(key(record));
            var result = live.module.dispatch("schedule.run",
                context(record, {id: id, key: task, payload: payload}));
            if (result.error is String && result.error != "") {
                throw new Exception(result.error);
            }
            return true;
        }, () -> false);
    }

    public static function route(id:String, directory:String, request:Request,
            handler:AbstractHandler):AbstractResponse {
        return withRoute(id, directory, () -> handler.execute(request),
            () -> ResponseBuilder.asString("Not found.", 404));
    }

    public static function validateRoute(id:String, directory:String,
            handler:AbstractHandler):Bool {
        // An inactive generation must reach execute's 404 without running unloaded plugin code.
        return withRoute(id, directory, () -> handler.validate(), () -> true);
    }

    public static function routeValidationFailure(id:String, directory:String, request:Request,
            handler:AbstractHandler):AbstractResponse {
        return withRoute(id, directory, () -> {
            if (Std.isOfType(handler, ValidationResponder)) {
                var responder:ValidationResponder = cast handler;
                return responder.validationFailed(request);
            }
            return new StatusTemplate(422).execute(request);
        }, () -> ResponseBuilder.asString("Not found.", 404));
    }

    public static function invoke(record:PackageRecord, event:String, data:Dynamic,
            strict:Bool = false):Dynamic {
        var moduleKey = key(record);
        locks.acquire(moduleKey);
        try {
            var live = modules.get(moduleKey);
            if (live == null || record.directory == null
                || PackageData.activeDirectory(record.id) != record.directory) {
                locks.release(moduleKey);
                return {};
            }
            var result = live.module.dispatch(event, context(record, data));
            locks.release(moduleKey);
            return result;
        } catch (error:Dynamic) {
            locks.release(moduleKey);
            if (strict) {
                throw error;
            }
            InstalledPackage.query.where("id", record.id)
                .where("directory", record.directory)
                .update(["enabled" => 0, "last_error" => Std.string(error).substr(0, 2000)]);
            ContentCache.changed("extensions");
            try {
                stop(record);
            } catch (cleanup:Dynamic) {}
            return {};
        }
    }

    public static function navigation(location:String, capabilities:Array<String>):Array<Dynamic> {
        var items:Array<Dynamic> = [];
        for (record in PackageData.forEvent("ui.navigation", "plugin")) {
            var response = invoke(record, "ui.navigation",
                {location: location, capabilities: capabilities});
            if (!Std.isOfType(response.items, Array)) {
                continue;
            }
            var entries:Array<Dynamic> = response.items;
            for (entry in entries.slice(0, 12)) {
                if (entry != null
                    && Std.isOfType(entry.label, String)
                    && entry.label.length <= 100
                    && Std.isOfType(entry.href, String)
                    && StringTools.startsWith(entry.href, "/")
                    && !StringTools.startsWith(entry.href, "//")
                    && entry.href.indexOf("\\") < 0
                    && !~/[\x00-\x20]/.match(entry.href)) {
                    items.push({
                        id: '${record.id}-${items.length}',
                        label: entry.label,
                        href: entry.href,
                        icon: Std.isOfType(entry.icon, String) ? entry.icon : "file"
                    });
                }
            }
        }
        return items;
    }

    public static function assets():Array<PluginAsset> {
        var result:Array<PluginAsset> = [];
        for (record in PackageData.forEvent("site.assets", "plugin")) {
            var manifest = PackageManifest.parse(record.manifest);
            result.push({
                id: record.id,
                module: PackageStorage.assetUrl(record, manifest.module),
                stylesheet: PackageStorage.assetUrl(record, manifest.stylesheet),
                settings: PackageSettings.values(manifest, record.settings, false)
            });
        }
        return result;
    }

    public static function blocks(event:String, data:Dynamic):Array<PluginBlock> {
        var result:Array<PluginBlock> = [];
        var slots = [
            "site.top",
            "site.footer",
            "site.before-footer",
            "content.before",
            "content.after",
            "dashboard"
        ];
        for (record in PackageData.forEvent(event)) {
            var response = invoke(record, event, data);
            if (!Std.isOfType(response.blocks, Array)) {
                continue;
            }
            var blocks:Array<Dynamic> = response.blocks;
            if (blocks.length > 16) {
                continue;
            }
            for (index in 0...blocks.length) {
                var block = blocks[index];
                if (block != null && Std.isOfType(block.slot, String)
                    && slots.contains(block.slot) && Std.isOfType(block.content, String)
                    && block.content.length <= 10000) {
                    result.push({
                        id: '${record.id}-${index}',
                        slot: block.slot,
                        content: block.content
                    });
                }
            }
        }
        return result;
    }

    public static function saving(document:Dynamic):String {
        for (record in PackageData.forEvent("content.saving")) {
            var response = invoke(record, "content.saving", {document: document}, true);
            if (Std.isOfType(response.error, String) && response.error != "") {
                return response.error.substr(0, 500);
            }
        }
        return "";
    }

    public static function saved(document:Dynamic):Void {
        for (record in PackageData.forEvent("content.saved")) {
            invoke(record, "content.saved", {document: document});
        }
    }

    public static function render(document:Dynamic):String {
        var content:String = document.content;
        for (record in PackageData.forEvent("content.render")) {
            var response = invoke(record, "content.render", {document: document, content: content});
            if (Std.isOfType(response.content, String)
                && response.content.length <= 100000
                && MediaStorage.contentUsesStoredImages(response.content)) {
                content = response.content;
            }
        }
        return content;
    }
}
