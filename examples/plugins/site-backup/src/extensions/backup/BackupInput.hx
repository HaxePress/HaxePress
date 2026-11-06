package extensions.backup;

#if jvm
import haxe.Exception;
import haxe.io.Bytes;
import haxe.io.Input;
import java.security.MessageDigest;

/** Read a source in bounded chunks while enforcing its declared budget. */
class BackupInput extends Input {
    final source:Input;
    final limit:Int;
    final digests:Null<Array<MessageDigest>>;

    public var count(default, null) = 0;

    public function new(source:Input, limit:Int, ?digests:Array<MessageDigest>) {
        this.source = source;
        this.limit = limit;
        this.digests = digests;
    }

    public override function readBytes(buffer:Bytes, offset:Int, length:Int):Int {
        var received = source.readBytes(buffer, offset, length);
        if (received > limit - count) {
            throw new Exception("The backup exceeds its size limit.");
        }
        count += received;
        if (digests != null) {
            for (digest in digests) {
                digest.update(buffer.getData(), offset, received);
            }
        }
        return received;
    }

    public override function close():Void {
        source.close();
    }
}
#end
