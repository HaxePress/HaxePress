package hx.press.view;

import haxe.io.Path;
import haxe.Exception;
import hx.press.packages.BuiltInTheme;
import hx.press.packages.PackageData;
import hx.press.packages.PackageData.PackageRecord;
import hx.press.packages.PackageManifest;
import hx.press.packages.ThemeData;
import hx.press.view.ViewEngine.ViewTarget;
import hx.well.facades.Storage;
import hx.well.http.Request;
import hx.well.storage.StorageDisk;
import wellout.check.ComponentLibrary;
import wellout.render.TemplateSet;
#if (target.threaded)
import sys.thread.Mutex;
#end

/**
    Public pages for the active (or previewed) theme. A packaged theme
    ships Wellout templates in the folder its manifest names as
    `assets.views`; its pages and components are looked up first, then the
    application's core components. Themes without views, such as the
    built-in Simple theme, use the application pages.

    Theme templates are untrusted input: they are checked with the element
    policy for installed templates and rendered within budgets.
**/
class ThemeViews {
    static inline final MAX_TEMPLATES = 200;
    static inline final MAX_TEMPLATE_BYTES = 262144;
    static inline final MAX_SETS = 16;

    /** The design template the theme builder's canvas shows, set for its frame request. **/
    public static inline final CANVAS_TEMPLATE = "hx.press.theme.canvas";

    static final sets:Map<String, TemplateSet> = [];
    static final order:Array<String> = [];
    #if (target.threaded)
    static final lock = new Mutex();
    #end

    public static function target(name:String, request:Null<Request>):Null<ViewTarget> {
        var theme:Dynamic = View.sharedValue(request, "theme");
        if (theme == null) {
            theme = ThemeData.active();
        }
        var namespace = theme == null ? BuiltInTheme.ID : Std.string(theme.id);
        var mapper = PreviewLinks.mapper(theme, request);
        var fallback = fallbackName(request);
        if (theme != null
            && theme.studioSession != null
            && theme.design != null
            && request != null) {
            // The builder edits the draft on an interactive canvas instead of the published page.
            request.setAttribute(CANVAS_TEMPLATE, name);
            return new ViewTarget(ViewEngine.application, "Admin/DesignCanvas", "cms", null, null);
        }
        if (theme != null && theme.layout == "builder" && theme.design != null) {
            var design = DesignViews.compiled(Std.string(theme.id), theme.design);
            var scope:Null<String> = theme.studioScope;
            for (candidate in [scope, name, fallback, "Home"]) {
                if (candidate != null && design.set.library.owns(candidate)) {
                    return new ViewTarget(design.set, candidate, namespace, null, mapper, true);
                }
            }
        }
        var set = theme == null || theme.built_in == true ? null : packageSet(Std.string(theme.id));
        if (set != null) {
            for (candidate in [name, fallback]) {
                if (set.library.owns(candidate)) {
                    return new ViewTarget(set, candidate, namespace, theme.assetBase, mapper, true);
                }
            }
        }
        var template = ViewEngine.library.has(name) ? name : fallback;
        return new ViewTarget(ViewEngine.application, template, namespace, null, mapper);
    }

    static function fallbackName(request:Null<Request>):String {
        var fallback:Null<String> = request == null ? null : request.getAttribute("hx.press.theme.fallback",
            null);
        return fallback == null ? "Home" : fallback;
    }

    /** The template set of a packaged theme with views, or null. **/
    static function packageSet(id:String):Null<TemplateSet> {
        var record = PackageData.one(id);
        if (record == null) {
            return null;
        }
        var manifest = PackageManifest.parse(record.manifest);
        if (manifest.views == "") {
            return null;
        }
        var key = '${record.id}:${record.directory}:${manifest.views}';
        var cached = cachedSet(key);
        if (cached != null) {
            return cached;
        }
        var disk = Storage.disk("extensions");
        var sources = load(disk, 'installed/${record.directory}/${manifest.views}');
        var library = new ComponentLibrary(ViewEngine.contract, ViewEngine.library, false);
        for (name => source in sources) {
            library.add(name, source);
        }
        var set = new TemplateSet(ViewEngine.contract, ViewEngine.runtime, library);
        storeSet(key, set);
        return set;
    }

    /** Reads every template of a views folder, keyed by file name without `.well.html`. **/
    static function load(disk:StorageDisk, folder:String):Map<String, String> {
        var sources:Map<String, String> = [];
        if (!disk.directoryExists(folder)) {
            return sources;
        }
        var count = 0;
        for (file in disk.files(folder, true)) {
            if (!StringTools.endsWith(file, ".well.html")) {
                continue;
            }
            count++;
            if (count > MAX_TEMPLATES) {
                throw new Exception('A theme may contain at most ${MAX_TEMPLATES} templates.');
            }
            if (disk.size(file) > MAX_TEMPLATE_BYTES) {
                throw new Exception('The theme template ${file} is larger than 256 KB.');
            }
            var base = Path.withoutDirectory(file);
            var name = base.substr(0, base.length - ".well.html".length);
            if (!~/^[A-Za-z][A-Za-z0-9_-]{0,79}$/.match(name)) {
                throw new Exception('The theme template name ${name} is not allowed.');
            }
            sources.set(name, disk.get(file));
        }
        return sources;
    }

    /**
        Checks a theme package's templates when it is installed, so a theme
        that does not compile is rejected with the first problem's position.
    **/
    public static function inspectPackage(disk:StorageDisk, folder:String):Void {
        if (!disk.directoryExists(folder)) {
            throw new Exception("The package is missing its declared views folder.");
        }
        var sources = load(disk, folder);
        var library = new ComponentLibrary(ViewEngine.contract, ViewEngine.library, false);
        for (name => source in sources) {
            library.add(name, source);
        }
        for (name => source in sources) {
            var result = library.check(name);
            for (diagnostic in result.diagnostics) {
                if (diagnostic.isError()) {
                    throw new Exception('${name}.well.html:${diagnostic.position}: ${diagnostic.message}');
                }
            }
        }
    }

    static function cachedSet(key:String):Null<TemplateSet> {
        #if (target.threaded)
        lock.acquire();
        var found = sets.get(key);
        lock.release();
        return found;
        #else
        return sets.get(key);
        #end
    }

    static function storeSet(key:String, set:TemplateSet):Void {
        #if (target.threaded)
        lock.acquire();
        #end
        if (!sets.exists(key)) {
            order.push(key);
            if (order.length > MAX_SETS) {
                sets.remove(order.shift());
            }
        }
        sets.set(key, set);
        #if (target.threaded)
        lock.release();
        #end
    }
}
