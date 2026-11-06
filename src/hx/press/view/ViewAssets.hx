package hx.press.view;

import haxe.DynamicAccess;
import haxe.Timer;
import haxe.Json;
import hx.well.facades.Storage;
#if (target.threaded)
import sys.thread.Mutex;
#end

typedef ManifestEntry = {
    var file:String;
    @:optional var css:Array<String>;
    @:optional var imports:Array<String>;
}

/**
    Public URLs of built assets: stylesheets and island modules from the
    Vite manifest in `public/build/.vite/manifest.json`. The manifest is
    read again when it changes, so a rebuild needs no restart.
**/
class ViewAssets {
    static inline final MANIFEST = "build/.vite/manifest.json";
    static inline final BASE = "/build/";

    static var entries:Map<String, ManifestEntry> = [];
    static var loadedAt = -1.0;
    static var checkedAt = 0.0;
    #if (target.threaded)
    static final lock = new Mutex();
    #end

    /** The URL of a built file by its source path, such as `resources/css/admin.css`. **/
    public static function url(source:String):String {
        var entry = entry(source);
        return entry == null ? "" : '${BASE}${entry.file}';
    }

    /** Changes whenever the front-end is rebuilt: the build manifest's modification time. **/
    public static function version():String {
        refresh();
        return loadedAt < 0 ? "" : Std.string(loadedAt);
    }

    /** Stylesheets a built module imports, such as the CSS of an island. **/
    public static function stylesheets(source:String):Array<String> {
        var entry = entry(source);
        if (entry == null || entry.css == null) {
            return [];
        }
        return [for (file in entry.css) '${BASE}${file}'];
    }

    static function entry(source:String):Null<ManifestEntry> {
        refresh();
        return entries.get(source);
    }

    static function refresh():Void {
        var now = Timer.stamp();
        if (loadedAt >= 0 && now - checkedAt < 2) {
            return;
        }
        #if (target.threaded)
        lock.acquire();
        #end
        try {
            checkedAt = now;
            var disk = Storage.disk("public");
            if (disk.fileExists(MANIFEST)) {
                var modified = disk.lastModified(MANIFEST);
                if (modified != loadedAt) {
                    var parsed:DynamicAccess<ManifestEntry> = Json.parse(disk.get(MANIFEST));
                    var next:Map<String, ManifestEntry> = [];
                    for (key => value in parsed) {
                        next.set(key, value);
                    }
                    entries = next;
                    loadedAt = modified;
                }
            }
        } catch (error:Dynamic) {
            trace('Could not read the asset manifest: ${error}');
        }
        #if (target.threaded)
        lock.release();
        #end
    }
}
