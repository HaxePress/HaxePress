package hx.press;

import hx.well.http.ResponseSlice;
import wellout.WriterPool;

/**
    Encodes text response bodies into reused UTF-8 buffers. The HTTP driver
    writes each buffer without copying and releases it once the bytes are sent.
**/
class ResponseBodies {
    static final pool = new WriterPool(16, 65536, 1048576);

    public static function encode(text:String):ResponseSlice {
        var writer = pool.acquire();
        writer.trusted(text);
        return new ResponseSlice(writer.bytes, writer.length, () -> pool.release(writer));
    }
}
