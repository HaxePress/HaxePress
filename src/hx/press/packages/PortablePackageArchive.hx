package hx.press.packages;

#if (cpp || php)
import haxe.Exception;
import haxe.io.Bytes;
import haxe.io.BytesInput;
import haxe.zip.Reader;
import hx.well.storage.StorageDisk;
import haxe.io.Eof;
import hx.press.packages.PackageEntryInput.ArchiveBudget;
#if php
import php.Global;
import php.Syntax;
#else
import haxe.zip.InflateImpl;
#end

#if php
/**
    Inflates one raw deflate stream of an archive with PHP's zlib. It is
    given a small slice of input at a time, so the output of one call stays
    small (deflate expands at most about 1:1032) and the entry's limits are
    checked as it streams.
**/
private class NativeInflater {
    static inline final SLICE = 1024;

    final archive:String;
    final start:Int;
    final context:Dynamic;
    var offset:Int;
    var pending = "";
    var pendingOffset = 0;

    public var finished(default, null) = false;

    /** The archive position after the stream, once it is `finished`. **/
    public var end(default, null) = -1;

    public function new(archive:Bytes, start:Int) {
        this.archive = archive.toString();
        this.start = start;
        offset = start;
        context = Syntax.code("\\inflate_init(\\ZLIB_ENCODING_RAW)");
    }

    public function readBytes(buffer:Bytes, position:Int, size:Int):Int {
        while (pendingOffset >= Global.strlen(pending)) {
            if (finished) {
                return 0;
            }
            var slice = Global.substr(archive, offset, SLICE);
            if (slice == "") {
                throw new Exception("The ZIP entry ends before its compressed data.");
            }
            var output:Dynamic = Syntax.code("@\\inflate_add({0}, {1}, \\ZLIB_SYNC_FLUSH)",
                context, slice);
            if (Syntax.strictEqual(output, false)) {
                throw new Exception("The ZIP entry is not valid deflate data.");
            }
            pending = output;
            pendingOffset = 0;
            if (Syntax.code("\\inflate_get_status({0}) === \\ZLIB_STREAM_END", context)) {
                finished = true;
                // Bytes after the stream in the last slice belong to the next record.
                var consumed:Int = Syntax.code("\\inflate_get_read_len({0})", context);
                end = start + consumed;
            } else {
                offset += Global.strlen(slice);
            }
        }
        var available = Global.strlen(pending) - pendingOffset;
        var count = size < available ? size : available;
        buffer.blit(position, Bytes.ofString(Global.substr(pending, pendingOffset, count)), 0,
            count);
        pendingOffset += count;
        return count;
    }
}
#end

/** Streams bounded ZIP entries through Haxe's ZIP reader and a raw inflater: zlib on PHP. */
class PortablePackageArchive {
    public static function unpack(bytes:Bytes, destination:String, disk:StorageDisk):Void {
        var input = new BytesInput(bytes);
        var reader = new Reader(input);
        var seen:Map<String, Bool> = [];
        var buffer = Bytes.alloc(8192);
        var budget:ArchiveBudget = {bytes: 0};
        var count = 0;
        var entry = reader.readEntryHeader();
        while (entry != null) {
            count++;
            if (count > SafePackageArchive.MAX_FILES) {
                throw new Exception("The package contains more than 256 files and directories.");
            }
            var directory = StringTools.endsWith(entry.fileName, "/");
            var name = directory ? entry.fileName.substr(0,
                entry.fileName.length - 1) : entry.fileName;
            if (!PackageManifest.safePath(name)) {
                throw new Exception("The package contains an unsafe file path.");
            }
            var key = name.toLowerCase();
            if (seen.exists(key)) {
                throw new Exception("The package contains duplicate file paths.");
            }
            seen.set(key, true);
            if (entry.dataSize < 0
                || entry.fileSize < 0
                || entry.fileSize > SafePackageArchive.MAX_FILE_BYTES
                || entry.dataSize > bytes.length - input.position) {
                throw new Exception("The ZIP entry has an invalid or excessive size.");
            }
            if (!entry.compressed && entry.crc32 == null) {
                throw new Exception("Stored ZIP entries must declare their size and checksum.");
            }
            var path = '${destination}/${name}';
            var start = input.position;
            #if php
            var inflater = entry.compressed ? new NativeInflater(bytes, start) : null;
            #else
            var inflater = entry.compressed ? new InflateImpl(input, false, false) : null;
            #end
            var storedRead = 0;
            var stream = new PackageEntryInput((buffer, position, size) -> {
                if (inflater != null) {
                    return inflater.readBytes(buffer, position, size);
                }
                var remaining = entry.dataSize - storedRead;
                if (remaining <= 0) {
                    return 0;
                }
                var read = input.readBytes(buffer, position, Std.int(Math.min(size, remaining)));
                storedRead += read;
                return read;
            }, budget, directory);
            if (directory) {
                disk.makeDirectory(path);
                try {
                    while (true) {
                        stream.readBytes(buffer, 0, buffer.length);
                    }
                } catch (_:Eof) {}
            } else {
                disk.writeStream(path, stream);
            }
            #if php
            if (inflater != null) {
                if (!inflater.finished) {
                    throw new Exception("The ZIP entry is not valid deflate data.");
                }
                input.position = inflater.end;
            }
            #end
            var compressedSize = input.position - start;
            if (entry.crc32 == null) {
                entry.crc32 = input.readInt32();
                if (entry.crc32 == 0x08074b50) {
                    entry.crc32 = input.readInt32();
                }
                entry.dataSize = input.readInt32();
                entry.fileSize = input.readInt32();
            }
            if (entry.fileSize != stream.length || entry.dataSize != compressedSize
                || !stream.matches(entry.crc32)) {
                throw new Exception("The ZIP entry size or checksum is invalid.");
            }
            entry = reader.readEntryHeader();
        }
    }
}
#end
