package hx.press.packages;

import haxe.Exception;
import haxe.crypto.Crc32;
import haxe.io.Bytes;
import haxe.io.Eof;
import haxe.io.Input;
#if php
import php.Syntax;
#end

typedef ArchiveBudget = {
    var bytes:Int;
}

/** Exposes one ZIP entry as a bounded Input for Storage.writeStream. */
class PackageEntryInput extends Input {
    var reader:(Bytes, Int, Int) -> Int;
    var budget:ArchiveBudget;
    var directory:Bool;
    #if php
    // PHP's hash extension computes the checksum natively, instead of byte by byte.
    var crc:Dynamic = Syntax.code("\\hash_init('crc32b')");
    #else
    var crc = new Crc32();
    #end
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
        #if php
        Syntax.code("\\hash_update({0}, {1})", crc, buffer.getString(position, read));
        #else
        crc.update(buffer, position, read);
        #end
        return read;
    }

    /** Whether the bytes read have the CRC-32 that a ZIP header stores as `expected`. **/
    public function matches(expected:Int):Bool {
        #if php
        // `hash` gives the checksum as unsigned hexadecimal; the header field is a signed Int.
        return Syntax.code("(({0}) & 0xFFFFFFFF) === \\hexdec(\\hash_final({1}))", expected, crc);
        #else
        return crc.get() == expected;
        #end
    }
}
