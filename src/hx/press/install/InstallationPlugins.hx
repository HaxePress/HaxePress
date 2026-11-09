package hx.press.install;

#if jvm
import haxe.Exception;
import hx.press.CmsVersion;
import hx.press.http.BodyLimits;
import hx.press.content.ContentColumns;
import hx.press.content.ContentColumns.ContentColumn;
import hx.press.packages.BuiltInPlugins;
import hx.press.packages.PackageManifest;
import hx.press.packages.PackageManifest.ManifestData;
import hx.press.packages.SafePackageArchive;
import hx.press.plugins.PluginHost;
import hx.press.plugins.PluginMiddleware;
import hx.press.plugins.PluginModule;
import hx.press.plugins.PluginRuntime;
import hx.press.view.PluginViews;
import hx.press.view.View;
import hx.well.facades.Storage;
import hx.well.handler.AbstractHandler;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.ResponseStatic.abort;
import hx.well.route.Route;
import hx.well.route.RouteElement;
import sys.thread.Thread;
import wellout.SafeHtml;

/** A bundled plugin running before the site is installed. **/
private class StagedPlugin {
    public final id:String;
    public final root:String;
    public final manifest:ManifestData;
    public final module:PluginModule;
    public var routes:Array<RouteElement> = [];
    public var middlewares:Array<PluginMiddleware> = [];
    public var columns:Array<ContentColumn> = [];

    public function new(id:String, root:String, manifest:ManifestData, module:PluginModule) {
        this.id = id;
        this.root = root;
        this.manifest = manifest;
        this.module = module;
    }
}

/** Runs a staged plugin's route with the plugin recorded as the request's owner. **/
private class StagedRouteHandler extends AbstractHandler {
    final id:String;
    final handler:AbstractHandler;

    public function new(id:String, handler:AbstractHandler) {
        super();
        this.id = id;
        this.handler = handler;
    }

    public function execute(request:Request):AbstractResponse {
        request.setAttribute(PluginRuntime.CURRENT, {id: id, directory: null});
        return handler.execute(request);
    }

    public override function validate():Bool {
        return handler.validate();
    }
}

/** The host of a plugin during installation: no administration, permissions or schedules yet. **/
private class InstallationPluginHost implements PluginHost {
    public function new() {}

    public function admin(routes:Void->Void):Void {}

    public function can(capability:String):Bool {
        return false;
    }

    public function schedule(pluginId:String, key:String, intervalSeconds:Int,
        ?payload:String):Void {}

    public function saveSchedule(pluginId:String, key:String, intervalSeconds:Int, payload:String,
            enabled:Bool, ?nextRun:Float):Void {
        throw new Exception("Scheduled tasks start after installation.");
    }

    public function schedules(pluginId:String, limit:Int):String {
        return "[]";
    }

    public function unschedule(pluginId:String, key:String):Bool {
        return false;
    }
}

/**
    Bundled plugins that take part in installation. While HaxePress is not
    installed, plugins shipped with the application whose manifest
    subscribes to the `installation` hook are unpacked from their archives
    and started with the context `phase: "installation"`. They register
    routes with `Installation.routes` and may offer a step on the
    installation page: the `installation.panel` event returns the name of
    one of their templates and its props. They stop once installation
    completes; the installed site then starts its plugins as usual.
**/
class InstallationPlugins {
    static inline final WORKSPACE = "installation";
    static inline final ASSET_PATH = "/admin/install/assets";
    static final staged:Array<StagedPlugin> = [];
    static var assetRoutes:Array<RouteElement> = [];

    public static function start():Void {
        if (!InstallationState.pending || staged.length > 0) {
            return;
        }
        var archives = Storage.disk("bundled");
        var extensions = Storage.disk("extensions");
        for (bundle in BuiltInPlugins.bundles()) {
            var archive = BuiltInPlugins.archive(bundle);
            if (!archives.fileExists(archive)) {
                continue;
            }
            var id = 'plugin-${bundle.slug}';
            var folder = '${WORKSPACE}/${bundle.slug}';
            try {
                if (extensions.directoryExists(folder)) {
                    extensions.deleteDirectory(folder);
                }
                var inspected = SafePackageArchive.extract(archives.getBytes(archive), folder,
                    extensions);
                var manifest = inspected.manifest;
                if (!manifest.hooks.contains("installation")) {
                    extensions.deleteDirectory(folder);
                    continue;
                }
                if (manifest.pluginId != bundle.identity
                    || manifest.entrypoint != bundle.entrypoint) {
                    throw new Exception("The bundled archive does not match its plugin.");
                }
                launch(id, inspected.root, manifest);
            } catch (error:Dynamic) {
                trace('Installation plugin ${id} could not start: ${Std.string(error)}');
                try {
                    extensions.deleteDirectory(folder);
                } catch (_:Dynamic) {}
            }
        }
        if (staged.length > 0) {
            assetRoutes = Route.batch(() -> Installation.routes(() -> {
                Route.get("/assets/{id}/{asset}", InstallationPlugins.asset).where("asset", ".+");
            }));
        }
    }

    static function launch(id:String, root:String, manifest:ManifestData):Void {
        var extensions = Storage.disk("extensions");
        var artifact = PackageManifest.serverArtifact(manifest);
        var module = new PluginModule(extensions.path('${root}/${artifact}'), manifest.entrypoint);
        var plugin = new StagedPlugin(id, root, manifest, module);
        if (manifest.views != "") {
            PluginViews.stage(id, extensions, '${root}/${manifest.views}', '${ASSET_PATH}/${id}/');
        }
        plugin.routes = Route.batch(() -> {
            plugin.columns = ContentColumns.collect(id, manifest.slug, () -> {
                plugin.middlewares = PluginMiddleware.collect(() -> {
                    module.create(new InstallationPluginHost(), context(plugin, {}));
                });
            });
        }, route -> {
            route.attribute("hx.press.plugin", id);
            var handler = route.getHandler();
            if (handler != null) {
                route.handler(new StagedRouteHandler(id, handler));
            }
            BodyLimits.register(route);
        });
        staged.push(plugin);
    }

    static function context(plugin:StagedPlugin, data:Dynamic):Dynamic {
        return {
            apiVersion: CmsVersion.pluginApiVersion,
            cmsVersion: CmsVersion.version,
            phase: "installation",
            locale: "en",
            packageInfo: {
                id: plugin.id,
                pluginId: plugin.manifest.pluginId,
                slug: plugin.manifest.slug,
                version: plugin.manifest.version
            },
            settings: {},
            site: {},
            data: data
        };
    }

    /**
        The steps installation plugins offer on the installation page, as
        rendered HTML. `step` describes where the visitor is: the step
        number, the chosen database driver, and the label of the verified
        database a source would install into (empty for a new SQLite file).
    **/
    public static function panels(step:Dynamic):Array<SafeHtml> {
        var result:Array<SafeHtml> = [];
        for (plugin in staged) {
            try {
                var offer:Dynamic = plugin.module.dispatch("installation.panel",
                    context(plugin, step));
                if (offer == null || !Std.isOfType(offer.view, String) || offer.view == "") {
                    continue;
                }
                var target = PluginViews.target(plugin.id, null, offer.view);
                var props:Dynamic = offer.props == null ? {} : offer.props;
                result.push(SafeHtml.trust(View.fragmentText(target, props)));
            } catch (error:Dynamic) {
                trace('Installation plugin ${plugin.id} could not offer its step: ${Std.string(error)}');
            }
        }
        return result;
    }

    static function asset(request:Request):AbstractResponse {
        var id = request.route("id");
        var file = request.route("asset");
        var plugin = Lambda.find(staged, item -> item.id == id);
        if (plugin == null || !PackageManifest.safePath(file)
            || !~/\.(js|mjs|css|json|png|svg|webp)$/.match(file)) {
            abort(404);
        }
        var disk = Storage.disk("extensions");
        var path = '${plugin.root}/public/${file}';
        if (!disk.fileExists(path)) {
            abort(404);
        }
        return disk.response(path, null, ["Cache-Control" => "no-store"]);
    }

    /**
        Removes the installation routes once the site is installed. The
        modules close a little later: the request that completed the
        installation may still be running their code.
    **/
    public static function retire():Void {
        if (staged.length == 0) {
            return;
        }
        var retired = staged.splice(0, staged.length);
        Route.batch(() -> {
            for (plugin in retired) {
                for (route in plugin.routes) {
                    BodyLimits.unregister(route);
                    Route.unregister(route);
                }
                for (middleware in plugin.middlewares) {
                    PluginMiddleware.remove(middleware);
                }
                for (column in plugin.columns) {
                    ContentColumns.remove(column);
                }
                PluginViews.unstage(plugin.id);
            }
            for (route in assetRoutes) {
                Route.unregister(route);
            }
            assetRoutes = [];
        });
        Thread.create(() -> {
            Sys.sleep(30);
            for (plugin in retired) {
                try {
                    Route.batch(() -> plugin.module.destroy());
                    plugin.module.close();
                } catch (error:Dynamic) {
                    trace('Installation plugin ${plugin.id} did not stop cleanly: ${Std.string(error)}');
                }
            }
            try {
                Storage.disk("extensions").deleteDirectory(WORKSPACE);
            } catch (_:Dynamic) {}
        });
    }
}
#end
