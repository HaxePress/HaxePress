package fixtures;

import haxe.Exception;
import haxe.io.Bytes;
import hx.well.websocket.AbstractWebSocketHandler;
import hx.well.websocket.WebSocketSession;
import sys.thread.Lock;
import sys.thread.Mutex;

class WebSocketLifecycleProbe extends AbstractWebSocketHandler {
    final gate = new Lock();
    final mutex = new Mutex();
    var opened = 0;
    var closed = 0;
    var errors = 0;
    var blocked = 0;

    public function new() {
        super();
    }

    public function status():Dynamic {
        var registered = [for (session in getSessions()) session.id];
        mutex.acquire();
        var result = {
            registered: registered.length,
            opened: opened,
            closed: closed,
            errors: errors,
            blocked: blocked
        };
        mutex.release();
        return result;
    }

    public function release():Void {
        gate.release();
    }

    public function onOpen(session:WebSocketSession):Void {
        mutex.acquire();
        opened++;
        mutex.release();
        session.send("opened");
    }

    public function onMessage(session:WebSocketSession, message:String):Void {
        switch (message) {
            case "close":
                session.close();
            case "fail":
                throw new Exception("Lifecycle fixture callback failure");
            case "block":
                mutex.acquire();
                blocked++;
                mutex.release();
                session.send("blocked");
                gate.wait(15);
                mutex.acquire();
                blocked--;
                mutex.release();
            default:
                session.send("received");
        }
    }

    public function onBinary(session:WebSocketSession, data:Bytes):Void {}

    public function onClose(session:WebSocketSession, code:Int, reason:String):Void {
        mutex.acquire();
        closed++;
        mutex.release();
        if (session.queryParams.get("throwClose") == "1") {
            throw new Exception("Lifecycle fixture close callback failure");
        }
    }

    public function onError(session:WebSocketSession, error:Exception):Void {
        mutex.acquire();
        errors++;
        mutex.release();
        session.close();
    }
}
