package hx.press.view;

import haxe.Exception;
import hx.press.packages.PackageData;
import hx.press.packages.PackageManifest;
import hx.press.packages.PackageStorage;
import hx.press.view.ViewEngine.ViewTarget;
import hx.well.facades.Storage;
import hx.well.storage.StorageDisk;
import wellout.check.ComponentLibrary;
import wellout.render.TemplateSet;
#if (target.threaded)
import sys.thread.Mutex;
#end

/** A plugin's compiled templates and the module URLs of its islands. **/
typedef PluginViewSet = {
    var set:TemplateSet;
    var islands:Map<String, String>;
    var assetBase:String;
}

/**
    Pages of plugins. A plugin ships Wellout templates in the folder its
    manifest names as `assets.views`; they are looked up first, then the
    application's components, such as `AdminLayout`. The folder's
    `contract.json` declares the view types its pages read and the islands
    it mounts:

    ```json
    {
      "views": {"ReportView": {"title": "String", "rows": "List<ReportRow>"}},
      "islands": {"report-chart": {"module": "chart.js", "props": {"rows": "Int"}, "messages": ["Loading"]}}
    }
    ```

    Island modules are files in the package's `public/` folder. A plugin
    renders its own pages with `Pages.view(name, props)` from its routes.
**/
class PluginViews {
    static inline final MAX_SETS = 16;
    static inline final MAX_CONTRACT_BYTES = 65536;

    static final sets:Map<String, PluginViewSet> = [];
    static final order:Array<String> = [];

    /** Sets of packages that run before they are installed, such as bundled installation plugins. **/
    static final staged:Map<String, PluginViewSet> = [];

    #if (target.threaded)
    static final lock = new Mutex();
    #end

    /** The page `name` of the plugin `id` whose installed files are in `directory`. **/
    public static function target(id:String, directory:Null<String>, name:String):ViewTarget {
        var views = directory == null ? stagedSet(id) : installedSet(id, directory);
        if (views == null) {
            throw new Exception('The plugin ${id} has no views.');
        }
        if (!views.set.library.owns(name)) {
            throw new Exception('The plugin ${id} has no page named ${name}.');
        }
        return new ViewTarget(views.set, name, id, views.assetBase, null, false, views.islands);
    }

    /** Compiles the views of a package that is not installed, available until `unstage`. **/
    public static function stage(id:String, disk:StorageDisk, folder:String,
            assetBase:String):Void {
        var views = build(disk, folder, assetBase);
        locked(() -> {
            staged.set(id, views);
            return true;
        });
    }

    public static function unstage(id:String):Void {
        locked(() -> staged.remove(id));
    }

    /**
        Checks a package's views when it is installed: its contract, and
        every template against it, so a plugin whose pages do not compile is
        rejected with the first problem's position.
    **/
    public static function inspectPackage(disk:StorageDisk, folder:String):Void {
        if (!disk.directoryExists(folder)) {
            throw new Exception("The package is missing its declared views folder.");
        }
        var views = build(disk, folder, "");
        for (name in ThemeViews.load(disk, folder).keys()) {
            var result = views.set.library.check(name);
            for (diagnostic in result.diagnostics) {
                if (diagnostic.isError()) {
                    throw new Exception('${name}.well.html:${diagnostic.position}: ${diagnostic.message}');
                }
            }
        }
    }

    static function installedSet(id:String, directory:String):Null<PluginViewSet> {
        var record = PackageData.one(id);
        if (record == null || record.directory != directory) {
            return null;
        }
        var manifest = PackageManifest.stored(record.manifest);
        if (manifest.views == "") {
            return null;
        }
        var key = '${record.id}:${record.directory}:${manifest.views}';
        var cached = locked(() -> sets.get(key));
        if (cached != null) {
            return cached;
        }
        var folder = '${PackageStorage.installed(directory)}/${manifest.views}';
        var views = build(Storage.disk("extensions"), folder, PackageStorage.assetBase(record));
        locked(() -> {
            if (!sets.exists(key)) {
                order.push(key);
                if (order.length > MAX_SETS) {
                    sets.remove(order.shift());
                }
            }
            sets.set(key, views);
            return true;
        });
        return views;
    }

    static function stagedSet(id:String):Null<PluginViewSet> {
        return locked(() -> staged.get(id));
    }

    static function build(disk:StorageDisk, folder:String, assetBase:String):PluginViewSet {
        var contract = ViewContract.build();
        var islands = PluginContract.declare(contract, readContract(disk, folder), assetBase);
        var library = new ComponentLibrary(contract, ViewEngine.library);
        for (name => source in ThemeViews.load(disk, folder)) {
            if (ViewEngine.library.has(name)) {
                throw new Exception('The plugin page ${name} has the name of an application template.');
            }
            library.add(name, source);
        }
        return {
            set: new TemplateSet(contract, ViewEngine.runtime, library,
                ViewEngine.store('plugin:${folder}:${assetBase}')),
            islands: islands,
            assetBase: assetBase
        };
    }

    static function readContract(disk:StorageDisk, folder:String):Dynamic {
        var path = '${folder}/${PluginContract.FILENAME}';
        if (!disk.fileExists(path)) {
            return {};
        }
        if (disk.size(path) > MAX_CONTRACT_BYTES) {
            throw new Exception("The views contract is larger than 64 KB.");
        }
        return PluginContract.parse(disk.get(path));
    }

    static function locked<T>(action:Void->T):T {
        #if (target.threaded)
        lock.acquire();
        try {
            var result = action();
            lock.release();
            return result;
        } catch (error:Dynamic) {
            lock.release();
            throw error;
        }
        #else
        return action();
        #end
    }
}
