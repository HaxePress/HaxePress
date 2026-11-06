package hx.press.packages;

import hx.press.packages.PackageData.PackageRecord;
import haxe.Exception;
import hx.well.facades.Storage;
import hx.well.facades.Environment;
import hx.well.storage.StoragePath;
import haxe.io.Path;

class PackageStorage {
    public static function root():String {
        return Storage.disk("extensions").path("");
    }

    public static inline var STAGING = "staging";

    public static function installed(directory:String):String {
        if (!PackageManifest.safePath(directory) || directory.indexOf("/") >= 0) {
            throw new Exception("Invalid installed package directory.");
        }
        return 'installed/${directory}';
    }

    public static function assetUrl(record:PackageRecord, asset:String,
            preview:Bool = false):String {
        if (asset == "") {
            return "";
        }
        return '${assetBase(record, preview)}${asset}';
    }

    public static function assetBase(record:PackageRecord, preview:Bool = false):String {
        var prefix = preview ? "/admin/extension-assets/" : "/extension-assets/";
        return '${prefix}${record.id}/${record.directory}/';
    }

    public static function remove(path:String):Void {
        var disk = Storage.disk("extensions");
        var relativePath = relative(path);
        if (disk.directoryExists(relativePath)) {
            disk.deleteDirectory(relativePath);
        } else if (disk.fileExists(relativePath)) {
            disk.delete(relativePath);
        }
    }

    /** Accept legacy staged-upload paths while keeping all operations disk-relative. */
    public static function relative(path:String):String {
        var normalized = Path.normalize(path);
        var storage = Environment.env("STORAGE_PATH", "storage");
        var extensions = Path.normalize('${storage}/extensions');
        var legacy = '${extensions}/';
        var absolute = '${root()}/';
        if (StringTools.startsWith(normalized, absolute)) {
            normalized = normalized.substr(absolute.length);
        } else if (StringTools.startsWith(normalized, legacy)) {
            normalized = normalized.substr(legacy.length);
        } else if (Path.isAbsolute(normalized)) {
            throw new Exception("Package files must remain inside their storage directory.");
        }
        var result = StoragePath.normalize(normalized);
        if (result == "") {
            throw new Exception("Package files must remain inside their storage directory.");
        }
        return result;
    }

    public static function installFrom(source:String, destination:String):Void {
        var disk = Storage.disk("extensions");
        var directory = relative(source);
        disk.makeDirectory(destination);
        // Inspected package trees contain at most SafePackageArchive.MAX_FILES entries.
        for (file in disk.files(directory, true)) {
            var suffix = file.substr(directory.length + 1);
            disk.move(file, '${destination}/${suffix}');
        }
        disk.deleteDirectory(directory);
    }
}
