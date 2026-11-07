package hx.press.plugins;

import haxe.Exception;
import haxe.io.Path;
import hx.well.storage.StorageDisk;
import hx.well.storage.StorageException;
import hx.press.packages.PackageManifest;

typedef PhpModuleData = {
    var namespace:String;
    var entrypoint:String;
    var classes:Map<String, String>;
}

/** Inspect the class map without evaluating uploaded PHP code. */
class PhpModuleDefinition {
    public static function inspect(disk:StorageDisk, path:String, entrypoint:String):PhpModuleData {
        var mapSize = fileSize(disk, path);
        if (mapSize < 0 || mapSize > 65536) {
            throw new Exception("The PHP module requires a class map smaller than 64 KB.");
        }
        var input:Dynamic = disk.json(path);
        var namespace = PackageManifest.text(input, "namespace", 80, true);
        var declaredEntrypoint = PackageManifest.text(input, "entrypoint", 180, true);
        if (!~/^CmsPlugin_[a-f0-9]{32}$/.match(namespace) || declaredEntrypoint != entrypoint) {
            throw new Exception("The PHP module must declare an isolated build namespace and the package entrypoint.");
        }
        var source:Dynamic = input.classes;
        if (source == null
            || !Reflect.isObject(source)
            || Std.isOfType(source, Array)
            || Std.isOfType(source, String)) {
            throw new Exception("The PHP module must declare a class-to-file map.");
        }
        var names = Reflect.fields(source);
        if (names.length == 0 || names.length > 128) {
            throw new Exception("The PHP module must contain between 1 and 128 classes.");
        }
        var classes:Map<String, String> = [];
        var seen:Map<String, Bool> = [];
        var directory = Path.directory(path);
        for (name in names) {
            var file = PackageManifest.text(source, name, 240, true);
            var qualifiedName = name.split("\\").join(".");
            if (!StringTools.startsWith(name, '${namespace}\\')
                || !~/^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)+$/.match(qualifiedName)
                || !PackageManifest.safePath(file)
                || !StringTools.endsWith(file, ".php")
                || seen.exists(name.toLowerCase())) {
                throw new Exception("The PHP module contains an invalid or duplicate class mapping.");
            }
            // `safePath` admits no empty, "." or ".." segment, so the path needs no normalizing.
            var modulePath = directory == "" ? file : '${directory}/${file}';
            var moduleSize = fileSize(disk, modulePath);
            if (moduleSize < 5 || moduleSize > 16 * 1024 * 1024) {
                throw new Exception("The PHP module is missing a declared class file.");
            }
            seen.set(name.toLowerCase(), true);
            classes.set(name, modulePath);
        }
        var className = entrypoint.split(".").join("\\");
        var nativeEntrypoint = '${namespace}\\${className}';
        if (!classes.exists(nativeEntrypoint)) {
            throw new Exception("The PHP module is missing its entrypoint class.");
        }
        return {namespace: namespace, entrypoint: nativeEntrypoint, classes: classes};
    }

    /** The size of a file, or -1 when it is missing or not a file: one Storage check per file. */
    static function fileSize(disk:StorageDisk, path:String):Int {
        return try disk.size(path) catch (_:StorageException) -1;
    }
}
