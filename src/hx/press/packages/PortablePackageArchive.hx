package hx.press.packages;

#if (cpp || php)
import haxe.Exception;
import haxe.io.Bytes;
import haxe.io.BytesInput;
import haxe.zip.InflateImpl;
import haxe.zip.Reader;
import hx.well.storage.StorageDisk;
import haxe.io.Eof;
import hx.press.packages.PackageEntryInput.ArchiveBudget;

/** Streams bounded ZIP entries through Haxe's native ZIP reader and raw inflater. */
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
            var inflater = entry.compressed ? new InflateImpl(input, false, false) : null;
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
                || entry.crc32 != stream.checksum()) {
                throw new Exception("The ZIP entry size or checksum is invalid.");
            }
            entry = reader.readEntryHeader();
        }
    }
}
#end
