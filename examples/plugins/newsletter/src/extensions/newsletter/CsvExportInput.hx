package extensions.newsletter;

import haxe.io.Bytes;
import haxe.io.Eof;
import haxe.io.Input;

/** Produces one bounded ORM batch at a time for Storage.writeStream. */
class CsvExportInput extends Input {
    var buffer = Bytes.ofString("Email,Subscribed at\r\n");
    var position = 0;
    var after = 0;
    var lastId:Int;
    var finished = false;

    public function new() {
        lastId = SubscriberData.exportLimit();
    }

    function refill():Void {
        if (finished || after >= lastId) {
            throw new Eof();
        }
        var subscribers = SubscriberData.exportBatch(after, lastId);
        if (subscribers.length == 0) {
            finished = true;
            throw new Eof();
        }
        var batch = new StringBuf();
        for (subscriber in subscribers) {
            batch.add(quote(subscriber.email));
            batch.add(",");
            batch.add(quote(Std.string(subscriber.created_at)));
            batch.add("\r\n");
        }
        after = subscribers[subscribers.length - 1].id;
        buffer = Bytes.ofString(batch.toString());
        position = 0;
    }

    public override function readByte():Int {
        if (position == buffer.length) {
            refill();
        }
        return buffer.get(position++);
    }

    public override function readBytes(destination:Bytes, offset:Int, length:Int):Int {
        if (length == 0) {
            return 0;
        }
        if (position == buffer.length) {
            refill();
        }
        var count = Std.int(Math.min(length, buffer.length - position));
        destination.blit(offset, buffer, position, count);
        position += count;
        return count;
    }

    public override function close():Void {
        finished = true;
    }

    static function quote(value:String):String {
        return '"' + StringTools.replace(value, '"', '""') + '"';
    }
}
