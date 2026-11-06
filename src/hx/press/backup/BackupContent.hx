package hx.press.backup;

#if jvm
import haxe.Exception;
import haxe.Json;
import haxe.crypto.Base64;
import haxe.crypto.Md5;
import haxe.io.Bytes;
import hx.press.packages.PackageArchiveInput.ArchiveSource;
import hx.well.storage.StorageDisk;

class BackupContent {
    public static inline var INDEX = "content.index.json";
    public static inline var MAX_ITEMS = 10000;
    public static inline var MAX_INDEX = 12 * MAX_ITEMS + 2;
    public static inline var MAX_RECORD = 4 * 1024 * 1024;
    static inline var PREFIX = "content/";

    public static function entryId(name:String):Null<Int> {
        if (!StringTools.startsWith(name, PREFIX)) {
            return null;
        }
        var start = PREFIX.length;
        var separator = name.indexOf("/", start);
        if (separator <= start || separator - start > 10) {
            return null;
        }
        var filename = name.substr(separator + 1);
        if (filename != "content" && filename != "content.hash") {
            return null;
        }
        var segment = name.substring(start, separator);
        var id = Std.parseInt(segment);
        return id != null && id > 0 && Std.string(id) == segment ? id : null;
    }

    public static function write(storage:StorageDisk, next:Void->Dynamic):Array<ArchiveSource> {
        var ids:Array<Int> = [];
        var files:Array<ArchiveSource> = [];
        var bytesWritten = 0;
        var row = next();
        while (row != null) {
            if (ids.length >= MAX_ITEMS) {
                throw new Exception("The backup contains too many content items.");
            }
            var id:Int = row.id;
            var path = 'content/${id}/content';
            var data = Bytes.ofString(Json.stringify(row,
                (_, value) -> value is Bytes ? {base64: Base64.encode(cast value)} : value));
            if (data.length > MAX_RECORD
                || data.length + 32 > SiteBackupArchive.MAX_EXPANDED - bytesWritten) {
                throw new Exception("The backup exceeds its content size limit.");
            }
            var hashPath = '${path}.hash';
            storage.put(path, data, "private");
            storage.put(hashPath, Md5.make(data).toHex(), "private");
            files.push(SiteBackupArchive.file(storage, path, path));
            files.push(SiteBackupArchive.file(storage, hashPath, hashPath));
            ids.push(id);
            bytesWritten += data.length + 32;
            row = next();
        }
        storage.put(INDEX, Json.stringify(ids), "private");
        files.push(SiteBackupArchive.file(storage, INDEX, INDEX));
        return files;
    }

    public static function ids(storage:StorageDisk, archivedIds:Array<Int>):Array<Int> {
        var data:Dynamic = Json.parse(storage.get(INDEX));
        if (!(data is Array) || data.length > MAX_ITEMS) {
            throw new Exception("The backup content index is invalid.");
        }
        var ids:Array<Int> = [];
        var last = 0;
        for (id in (cast data : Array<Dynamic>)) {
            if (!(id is Int) || id <= last) {
                throw new Exception("The backup content index is invalid.");
            }
            ids.push(id);
            last = id;
        }
        var expected = [for (id in ids) id => true];
        for (id in archivedIds) {
            if (!expected.exists(id)) {
                throw new Exception("The backup contains an unexpected content item.");
            }
        }
        return ids;
    }

    public static function read(storage:StorageDisk, id:Int,
            columns:Array<String>):Null<Map<String, Dynamic>> {
        var path = 'content/${id}/content';
        var hashPath = '${path}.hash';
        if (!storage.fileExists(path) || !storage.fileExists(hashPath)) {
            return null;
        }
        var bytes = storage.getBytes(path);
        if (Md5.make(bytes).toHex() != storage.get(hashPath)) {
            return null;
        }
        try {
            var record:Dynamic = Json.parse(bytes.toString());
            if (record == null || record.id != id
                || Reflect.fields(record).length != columns.length) {
                return null;
            }
            var values:Map<String, Dynamic> = [];
            for (column in columns) {
                if (!Reflect.hasField(record, column)) {
                    return null;
                }
                var value:Dynamic = Reflect.field(record, column);
                if (value != null
                    && !(value is String)
                    && !(value is Int)
                    && !(value is Float)
                    && !(value is Bool)) {
                    if (!(value.base64 is String) || Reflect.fields(value).length != 1) {
                        return null;
                    }
                    value = Base64.decode(value.base64);
                }
                values.set(column, value);
            }
            return values;
        } catch (_:Dynamic) {
            return null;
        }
    }
}
#end
