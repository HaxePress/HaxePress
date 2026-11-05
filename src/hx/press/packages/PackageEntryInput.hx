package hx.press.packages;

import haxe.Exception;
import haxe.crypto.Crc32;
import haxe.io.Bytes;
import haxe.io.Eof;
import haxe.io.Input;

typedef ArchiveBudget = {
    var bytes:Int;
}

/** Exposes one ZIP entry as a bounded Input for Storage.writeStream. */
class PackageEntryInput extends Input {
    var reader:(Bytes, Int, Int) -> Int;
    var budget:ArchiveBudget;
    var directory:Bool;
    var crc = new Crc32();
    var singleByte = Bytes.alloc(1);

    public var length(default, null):Int = 0;

    public function new(reader:(Bytes, Int, Int) -> Int, budget:ArchiveBudget, directory:Bool) {
        this.reader = reader;
        this.budget = budget;
        this.directory = directory;
    }

    public override function readByte():Int {
        readBytes(singleByte, 0, 1);
        return singleByte.get(0);
    }

    public override function readBytes(buffer:Bytes, position:Int, count:Int):Int {
        if (count == 0) {
            return 0;
        }
        var read = reader(buffer, position, count);
        if (read <= 0) {
            throw new Eof();
        }
        length += read;
        budget.bytes += read;
        if (length > SafePackageArchive.MAX_FILE_BYTES
            || budget.bytes > SafePackageArchive.MAX_EXPANDED_BYTES
            || (directory && length > 0)) {
            throw new Exception("The package expands beyond the allowed size.");
        }
        crc.update(buffer, position, read);
        return read;
    }

    public function checksum():Int {
        return crc.get();
    }
}
