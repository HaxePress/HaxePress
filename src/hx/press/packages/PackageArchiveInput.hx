package hx.press.packages;

import haxe.Exception;
import haxe.crypto.Crc32;
import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import haxe.io.Output;
import haxe.io.Eof;
import haxe.io.Input;
import haxe.zip.Entry;
import haxe.zip.Tools;
import haxe.zip.Writer;

typedef ArchiveSource = {
    var name:String;
    var size:Int;
    var open:Void->Input;
}

/** Native ZIP headers/CDR, with at most one bounded entry payload retained at a time. */
class PackageArchiveInput extends Input {
    final sources:Array<ArchiveSource>;
    final metadata = new ArchiveMetadataOutput();
    final writer:Writer;
    var index = 0;
    var bytes = Bytes.alloc(0);
    var position = 0;
    var pending:Null<Bytes>;
    var emitted = 0;
    var finished = false;

    public function new(sources:Array<ArchiveSource>) {
        if (sources.length > SafePackageArchive.MAX_FILES) {
            throw new Exception("The theme package contains too many files.");
        }
        this.sources = sources;
        var expanded:Float = 0;
        for (source in sources) {
            expanded += source.size;
            if (expanded > SafePackageArchive.MAX_EXPANDED_BYTES) {
                throw new Exception("The theme package exceeds the 32 MB expanded size limit.");
            }
        }
        writer = new Writer(metadata);
    }

    static function contents(source:ArchiveSource):Bytes {
        if (!PackageManifest.safePath(source.name) || source.size < 0
            || source.size > SafePackageArchive.MAX_FILE_BYTES) {
            throw new Exception("A theme package file exceeds the export limits.");
        }
        var input = source.open();
        try {
            var bytes = Bytes.alloc(source.size);
            input.readFullBytes(bytes, 0, bytes.length);
            var extra = false;
            try {
                input.readByte();
                extra = true;
            } catch (_:Eof) {}
            if (extra) {
                throw new Exception("A theme package file changed during export.");
            }
            input.close();
            return bytes;
        } catch (error:Dynamic) {
            input.close();
            throw error;
        }
    }

    function refill():Void {
        if (pending != null) {
            bytes = pending;
            pending = null;
        } else {
            if (finished) {
                throw new Eof();
            }
            if (index < sources.length) {
                var source = sources[index++];
                var data = contents(source);
                var entry:Entry = {
                    fileName: source.name,
                    fileSize: data.length,
                    fileTime: Date.now(),
                    compressed: false,
                    dataSize: data.length,
                    data: data,
                    crc32: Crc32.make(data)
                };
                Tools.compress(entry, 6);
                writer.writeEntryHeader(entry);
                pending = entry.data;
            } else {
                writer.writeCDR();
                finished = true;
            }
            bytes = metadata.take();
        }
        position = 0;
        if (bytes.length == 0) {
            refill();
        }
    }

    public override function readByte():Int {
        if (position == bytes.length) {
            refill();
        }
        if (++emitted > SafePackageArchive.MAX_BYTES) {
            throw new Exception("The theme ZIP exceeds the 64 MB package upload limit.");
        }
        return bytes.get(position++);
    }

    public override function readBytes(destination:Bytes, offset:Int, length:Int):Int {
        if (length == 0) {
            return 0;
        }
        if (position == bytes.length) {
            refill();
        }
        var count = Std.int(Math.min(length, bytes.length - position));
        if (emitted + count > SafePackageArchive.MAX_BYTES) {
            throw new Exception("The theme ZIP exceeds the 64 MB package upload limit.");
        }
        destination.blit(offset, bytes, position, count);
        emitted += count;
        position += count;
        return count;
    }

    public override function close():Void {
        finished = true;
        bytes = Bytes.alloc(0);
        pending = null;
        position = 0;
    }
}

private class ArchiveMetadataOutput extends Output {
    var buffer = new BytesBuffer();

    public function new() {}

    public override function writeByte(value:Int):Void {
        buffer.addByte(value);
    }

    public override function writeBytes(bytes:Bytes, position:Int, length:Int):Int {
        buffer.addBytes(bytes, position, length);
        return length;
    }

    public function take():Bytes {
        var bytes = buffer.getBytes();
        buffer = new BytesBuffer();
        return bytes;
    }
}
