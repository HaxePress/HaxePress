package extensions.backup;

#if jvm
import haxe.Exception;
import haxe.Int64;
import haxe.Json;
import haxe.crypto.Base64;
import haxe.io.Bytes;
import haxe.io.BytesInput;
import haxe.io.Eof;
import haxe.io.Input;
import hx.press.CmsVersion;
import hx.press.packages.PackageArchiveInput.ArchiveSource;
import hx.press.packages.PackageManifest;
import hx.well.database.schema.SchemaGrammar;
import hx.well.facades.Config;
import hx.well.storage.StorageDisk;
import java.io.ByteArrayOutputStream;
import java.io.NativeInput;
import java.security.MessageDigest;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;
import java.util.zip.ZipOutputStream;

typedef BackupSelection = {
    var content:Bool;
    var themes:Bool;
    var plugins:Bool;
}

typedef BackupManifest = {
    var format:String;
    var version:Int;
    var cmsVersion:String;
    var apiVersion:Int;
    var appKey:String;
    var sections:BackupSelection;
}

typedef ExtractedBackup = {
    var manifest:BackupManifest;
    var files:Array<String>;
    var md5:String;
    var intact:Bool;
    var contentIds:Array<Int>;
}

class SiteBackupArchive {
    public static inline var SCHEMA = "database/schema.json";
    public static inline var MAX_SCHEMA = 2 * 1024 * 1024;
    public static inline var CHECKSUM = "backup.md5";
    public static inline var CORE_CHECKSUM = "backup.core.md5";
    static inline var MANIFEST = "backup.json";
    static inline var FORMAT = "haxepress.backup";
    static inline var VERSION = 3;
    static inline var MANIFEST_LIMIT = 4096;
    static inline var PACKAGES = "extensions/installed/";
    public static inline var MAX_MANAGED_FILES = 4093;
    static inline var MAX_ENTRIES = MAX_MANAGED_FILES
        + BackupContent.MAX_ITEMS * 2
        + BackupTable.MAX_TABLES
        + 5;
    public static inline var MAX_EXPANDED = 256 * 1024 * 1024;

    public static function maxBytes():Int {
        var configured:Int = Config.get("http.max_content_length");
        return configured > 0 ? Std.int(Math.min(configured, 64 * 1024 * 1024)) : 64 * 1024 * 1024;
    }

    public static function manifest(sections:BackupSelection, appKey:String):ArchiveSource {
        var bytes = Bytes.ofString(Json.stringify({
            format: FORMAT,
            version: VERSION,
            cmsVersion: CmsVersion.version,
            apiVersion: CmsVersion.pluginApiVersion,
            appKey: appKey,
            sections: sections
        }));
        return {name: MANIFEST, size: bytes.length, open: () -> new BytesInput(bytes)};
    }

    public static function file(disk:StorageDisk, path:String, name:String):ArchiveSource {
        return {name: name, size: disk.size(path), open: () -> disk.readStream(path)};
    }

    public static function write(disk:StorageDisk, path:String, files:Array<ArchiveSource>):Void {
        if (files.length > MAX_ENTRIES - 2) {
            throw new Exception("The backup contains too many files.");
        }
        var total = 64;
        for (file in files) {
            if ((!allowed(file.name) && BackupContent.entryId(file.name) == null)
                || file.size < 0 || file.size > MAX_EXPANDED - total) {
                throw new Exception("The backup contains an invalid path or exceeds its expanded size limit.");
            }
            total += file.size;
        }
        var stream = new BackupZipInput(files, maxBytes());
        try {
            disk.writeStream(path, stream, "private");
        } catch (error:Dynamic) {
            stream.close();
            throw error;
        }
        stream.close();
    }

    public static function extract(disk:StorageDisk, path:String, target:StorageDisk,
            skipDamaged:Bool):ExtractedBackup {
        if (disk.size(path) > maxBytes()) {
            throw new Exception("The backup exceeds its upload limit.");
        }
        var zip = new ZipFile(disk.path(path));
        try {
            var result = extractEntries(zip, target, skipDamaged);
            zip.close();
            return result;
        } catch (error:Dynamic) {
            zip.close();
            throw error;
        }
    }

    static function extractEntries(zip:ZipFile, target:StorageDisk,
            skipDamaged:Bool):ExtractedBackup {
        if (zip.size() > MAX_ENTRIES) {
            throw new Exception("The backup contains too many files.");
        }
        var entries = zip.entries();
        var seen:Map<String, Bool> = [];
        var contentIds:Map<Int, Bool> = [];
        var files:Array<String> = [];
        var databaseFiles = 0;
        var total = 0;
        var digest = MessageDigest.getInstance("MD5");
        var core = MessageDigest.getInstance("MD5");
        var md5:Null<String> = null;
        var coreMd5:Null<String> = null;
        while (entries.hasMoreElements()) {
            var entry = entries.nextElement();
            var name = entry.getName();
            var size = Int64.toInt(entry.getSize());
            var key = SchemaGrammar.asciiLower(name);
            if (entry.isDirectory()
                || seen.exists(key)
                || size < 0
                || size > MAX_EXPANDED - total) {
                throw new Exception("The backup contains duplicate paths or exceeds its expanded size limit.");
            }
            seen.set(key, true);
            total += size;
            if (name == CHECKSUM || name == CORE_CHECKSUM) {
                var checksum = size == 32 ? readBounded(zip, entry, size) : null;
                if (checksum == null || !~/^[0-9a-f]{32}$/.match(checksum.toString())) {
                    throw new Exception("The backup MD5 checksum entry is invalid.");
                }
                if (name == CHECKSUM) {
                    if (entries.hasMoreElements()) {
                        throw new Exception("The backup MD5 checksum must be the last entry.");
                    }
                    md5 = checksum.toString();
                    break;
                }
                coreMd5 = checksum.toString();
                hashEntry(digest, name, size);
                digest.update(checksum.getData());
                continue;
            }
            var id = BackupContent.entryId(name);
            if (id != null) {
                contentIds.set(id, true);
                var validSize = StringTools.endsWith(name,
                    ".hash") ? size == 32 : size <= BackupContent.MAX_RECORD;
                var record = validSize ? readBounded(zip, entry, size) : null;
                if (record != null) {
                    hashEntry(digest, name, size);
                    digest.update(record.getData());
                    target.put(name, record, "private");
                }
                continue;
            }
            if (!allowed(name)
                || (name == MANIFEST && size > MANIFEST_LIMIT)
                || (name == BackupContent.INDEX && size > BackupContent.MAX_INDEX)
                || (name == SCHEMA && size > MAX_SCHEMA)) {
                throw new Exception("The backup contains an unexpected file.");
            }
            hashEntry(digest, name, size);
            hashEntry(core, name, size);
            var input = new BackupInput(new NativeInput(zip.getInputStream(entry)), size,
                [digest, core]);
            try {
                target.writeStream(name, input, "private");
            } catch (error:Dynamic) {
                input.close();
                throw error;
            }
            input.close();
            if (input.count != size) {
                throw new Exception("The backup contains an incomplete file.");
            }
            if (databaseEntry(name)) {
                databaseFiles++;
            } else if (name != MANIFEST && name != BackupContent.INDEX) {
                files.push(name);
            }
        }
        if (!seen.exists(MANIFEST)) {
            throw new Exception("The backup manifest is missing.");
        }
        var metadata = parse(target.get(MANIFEST));
        if (!seen.exists(SCHEMA) || databaseFiles > BackupTable.MAX_TABLES) {
            throw new Exception("The backup database files do not match its format.");
        }
        var ids = [for (id in contentIds.keys()) id];
        var hasIndex = seen.exists(BackupContent.INDEX);
        if (coreMd5 != Bytes.ofData(core.digest()).toHex()) {
            throw new Exception("The backup core MD5 checksum does not match.");
        }
        if (metadata.sections.content != hasIndex || (!hasIndex && ids.length > 0)) {
            throw new Exception("The backup content index does not match its selected sections.");
        }
        var intact = md5 != null && md5 == Bytes.ofData(digest.digest()).toHex();
        if (!intact && (md5 == null || !skipDamaged)) {
            throw new Exception("The backup MD5 checksum does not match.");
        }
        return {
            manifest: metadata,
            files: files,
            md5: md5,
            intact: intact,
            contentIds: ids
        };
    }

    /** A readable ZIP can still contain individual entries that fail to inflate. */
    static function readBounded(zip:ZipFile, entry:ZipEntry, size:Int):Null<Bytes> {
        var input:Null<NativeInput> = null;
        var bytes:Null<Bytes>;
        try {
            input = new NativeInput(zip.getInputStream(entry));
            bytes = input.read(size);
            try {
                input.readByte();
                bytes = null;
            } catch (_:Eof) {}
        } catch (_:Dynamic) {
            bytes = null;
        }
        if (input != null) {
            input.close();
        }
        return bytes;
    }

    static function parse(text:String):BackupManifest {
        var value:Dynamic = Json.parse(text);
        if (value == null
            || value.format != FORMAT
            || value.version != VERSION
            || value.cmsVersion != CmsVersion.version
            || value.apiVersion != CmsVersion.pluginApiVersion) {
            throw new Exception("Choose a backup created by this HaxePress release.");
        }
        var appKey:Dynamic = value.appKey;
        if (!(appKey is String) || !~/^[A-Za-z0-9+\/]{43}=$/.match(appKey)
            || Base64.decode(appKey).length != 32) {
            throw new Exception("The backup site key is invalid.");
        }
        var sections:Dynamic = value.sections;
        if (sections == null
            || !(sections.content is Bool)
            || !(sections.themes is Bool)
            || !(sections.plugins is Bool)
            || !(sections.content || sections.themes || sections.plugins)) {
            throw new Exception("The backup section list is invalid.");
        }
        return cast value;
    }

    static function allowed(name:String):Bool {
        if (StringTools.startsWith(name, PACKAGES)) {
            var directoryEnd = name.indexOf("/", PACKAGES.length);
            return directoryEnd > PACKAGES.length
                && PackageManifest.safePath(name.substring(PACKAGES.length, directoryEnd))
                && PackageManifest.safePath(name.substr(directoryEnd + 1));
        }
        return PackageManifest.safePath(name)
            && (name == MANIFEST
                || databaseEntry(name)
                || name == BackupContent.INDEX
                || StringTools.startsWith(name, "media/")
                || StringTools.startsWith(name, "themes/"));
    }

    static function databaseEntry(name:String):Bool {
        return name == SCHEMA || ~/^database\/[A-Za-z_][A-Za-z0-9_]{0,63}\.rows$/.match(name);
    }

    public static function hashEntry(digest:MessageDigest, name:String, size:Int):Void {
        digest.update(Bytes.ofString('${name.length}:${name}:${size}\n').getData());
    }
}

/** Feed ZIP compression one file block at a time to the Storage writer. */
private class BackupZipInput extends Input {
    final files:Array<ArchiveSource>;
    final limit:Int;
    final output = new ByteArrayOutputStream();
    final zip:ZipOutputStream;
    final digest = MessageDigest.getInstance("MD5");
    final core = MessageDigest.getInstance("MD5");
    final block = Bytes.alloc(65536);
    var pending = Bytes.alloc(0);
    var offset = 0;
    var index = 0;
    var written = 0;
    var remaining = 0;
    var coreEntry = false;
    var source:Null<Input>;
    var finished = false;

    public function new(files:Array<ArchiveSource>, limit:Int) {
        this.files = files;
        this.limit = limit;
        zip = new ZipOutputStream(output);
    }

    function refill():Void {
        while (offset == pending.length) {
            if (finished) {
                throw new Eof();
            }
            if (source == null && index == files.length) {
                var coreChecksum = writeChecksum(SiteBackupArchive.CORE_CHECKSUM, core);
                SiteBackupArchive.hashEntry(digest, SiteBackupArchive.CORE_CHECKSUM,
                    coreChecksum.length);
                digest.update(coreChecksum.getData());
                writeChecksum(SiteBackupArchive.CHECKSUM, digest);
                zip.finish();
                finished = true;
            } else {
                if (source == null) {
                    var file = files[index++];
                    source = file.open();
                    remaining = file.size;
                    zip.putNextEntry(new ZipEntry(file.name));
                    SiteBackupArchive.hashEntry(digest, file.name, file.size);
                    coreEntry = BackupContent.entryId(file.name) == null;
                    if (coreEntry) {
                        SiteBackupArchive.hashEntry(core, file.name, file.size);
                    }
                }
                var count = Std.int(Math.min(block.length, remaining));
                source.readFullBytes(block, 0, count);
                digest.update(block.getData(), 0, count);
                if (coreEntry) {
                    core.update(block.getData(), 0, count);
                }
                zip.write(block.getData(), 0, count);
                remaining -= count;
                if (remaining == 0) {
                    try {
                        source.readByte();
                        throw new Exception("A file changed while the backup was being prepared.");
                    } catch (_:Eof) {}
                    source.close();
                    source = null;
                    zip.closeEntry();
                }
            }
            pending = Bytes.ofData(output.toByteArray());
            output.reset();
            offset = 0;
            written += pending.length;
            if (written > limit) {
                throw new Exception("The backup exceeds its upload limit.");
            }
        }
    }

    function writeChecksum(name:String, digest:MessageDigest):Bytes {
        var checksum = Bytes.ofString(Bytes.ofData(digest.digest()).toHex());
        zip.putNextEntry(new ZipEntry(name));
        zip.write(checksum.getData(), 0, checksum.length);
        zip.closeEntry();
        return checksum;
    }

    public override function readBytes(buffer:Bytes, position:Int, length:Int):Int {
        if (length == 0) {
            return 0;
        }
        refill();
        var count = Std.int(Math.min(length, pending.length - offset));
        buffer.blit(position, pending, offset, count);
        offset += count;
        return count;
    }

    public override function close():Void {
        if (source != null) {
            source.close();
        }
        zip.close();
    }
}
#end
