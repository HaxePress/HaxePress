package extensions.newsletter;

import haxe.io.Bytes;
import haxe.io.Input;

/** Close the native Storage download stream before deleting its temporary file. */
class ExportInput extends Input {
    var source:Input;
    var cleanup:Void->Void;
    var closed = false;

    public function new(source:Input, cleanup:Void->Void) {
        this.source = source;
        this.cleanup = cleanup;
    }

    public override function readByte():Int {
        return source.readByte();
    }

    public override function readBytes(buffer:Bytes, position:Int, length:Int):Int {
        return source.readBytes(buffer, position, length);
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
