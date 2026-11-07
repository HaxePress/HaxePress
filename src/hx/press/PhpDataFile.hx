package hx.press;

#if php
import haxe.io.Path;
import hx.well.facades.Storage;
import hx.well.internal.SecureToken;
import php.Global;
import php.Syntax;

/**
    A PHP file of the local disk that returns data written by `var_export`:
    strings, numbers, booleans, null and arrays, never code. PHP starts the
    application for each request; opcache keeps these arrays in shared
    memory, so reading one costs neither parsing nor copying. A file that
    cannot be read or written is only a cache miss.
**/
class PhpDataFile {
    /** The array a file at a physical path returns, or null when it is missing. **/
    public static function read(file:String):Null<Dynamic> {
        // Storage resolves the path first; the include is the native runtime
        // boundary that opcache caches.
        var data:Dynamic = try Syntax.code("(@include {0})", file) catch (_:Dynamic) null;
        return Global.is_array(data) ? data : null;
    }

    /** Writes `value` to `path` on the local disk; `description` heads the file. **/
    public static function write(path:String, value:Dynamic, description:String):Void {
        var disk = Storage.disk("local");
        var exported:String = Syntax.code("var_export({0}, true)", value);
        var source = '<?php\n// ${description}: data only. Generated; do not edit.\nreturn ${exported};\n';
        // Write a private file and rename it, so concurrent requests never read part of one.
        var temporary = '${path}.${SecureToken.generate(12)}.tmp';
        try {
            disk.makeDirectory(Path.directory(path));
            disk.put(temporary, source);
            disk.move(temporary, path);
            if (Global.function_exists("opcache_invalidate")) {
                Syntax.code("opcache_invalidate({0}, true)", disk.path(path));
            }
        } catch (_:Dynamic) {
            try {
                disk.delete(temporary);
            } catch (_:Dynamic) {}
        }
    }
}
#end
