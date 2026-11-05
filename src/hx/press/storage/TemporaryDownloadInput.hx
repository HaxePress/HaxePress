package hx.press.storage;

import haxe.io.Bytes;
import haxe.io.Input;

/** The driver closes body inputs on success and disconnect; onAfter only covers success. */
class TemporaryDownloadInput extends Input {
    final source:Input;
    final cleanup:Void->Void;
    var closed = false;

    public function new(source:Input, cleanup:Void->Void) {
        this.source = source;
        this.cleanup = cleanup;
    }

    public override function readByte():Int {
        return source.readByte();
    }

    public override function readBytes(bytes:Bytes, position:Int, length:Int):Int {
        return source.readBytes(bytes, position, length);
    }

    public override function close():Void {
        if (closed) {
            return;
        }
        closed = true;
        try {
            source.close();
        } catch (error:Dynamic) {
            cleanup();
            throw error;
        }
        cleanup();
    }
}
