package hx.press.view;

import haxe.io.Bytes;
import hx.well.http.Response;
import hx.well.http.ResponseSlice;
import wellout.ByteWriter;
import wellout.WriterPool;

/**
    A rendered page. The driver writes the pooled buffer without copying
    and releases it after sending, so rendering a page creates no body
    string or byte copy.
**/
class ViewResponse extends Response {
    static final pool = new WriterPool(32, 32768, 2097152);

    var writer:Null<ByteWriter>;

    public static function acquire():ByteWriter {
        return pool.acquire();
    }

    public static function discard(writer:ByteWriter):Void {
        pool.release(writer);
    }

    public function new(writer:ByteWriter, status:Int = 200) {
        super(status);
        this.writer = writer;
        header("Content-Type", "text/html; charset=utf-8");
    }

    override public function toString():String {
        return writer == null ? "" : writer.toString();
    }

    override public function toBytes():Bytes {
        var bytes = writer == null ? Bytes.alloc(0) : writer.toBytes();
        contentLength = bytes.length;
        return bytes;
    }

    override public function slice():Null<ResponseSlice> {
        var current = writer;
        if (current == null) {
            return null;
        }
        return new ResponseSlice(current.bytes, current.length, () -> {
            if (writer == current) {
                writer = null;
            }
            pool.release(current);
        });
    }
}
