package hx.press.mcp;

import haxe.Exception;
import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import haxe.io.BytesInput;
import haxe.io.Eof;
import haxe.io.Encoding;
import haxe.io.Input;
import haxe.io.Output;
import hx.well.http.HttpHandler;
import hx.well.http.Request;
import hx.well.http.RequestStatic;
import hx.well.http.Response;
import hx.well.http.ResponseStatic;
import hx.well.http.driver.IDriverContext;
import hx.well.http.driver.socket.SocketRequestParser;
import hx.well.websocket.AbstractWebSocketHandler;

/** A response captured from an in-process request. **/
typedef InternalReply = {
    var status:Int;
    var headers:Map<String, String>;
    var body:Bytes;
}

/**
    Runs a request through the site's own routes, middleware and handlers
    inside the current request, and captures the response instead of
    sending it. MCP tools use it to call the administration panel exactly as
    a person's browser would, with the same validation and access checks.
    The caller's request and response context is restored afterwards.
**/
@:access(hx.well.http.Request)
@:access(hx.well.http.RequestStatic)
@:access(hx.well.http.ResponseStatic)
class InternalRequest {
    public static function send(method:String, path:String, headers:Map<String, String>,
            body:Null<Bytes>, attributes:Map<String, Dynamic>, limit:Int):InternalReply {
        var request = new Request();
        request.method = method;
        request.path = path;
        request.host = host();
        request.ip = "127.0.0.1";
        request.version = "HTTP/1.1";
        for (name => value in headers) {
            request.headers.set(name, value);
        }
        var content = body ?? Bytes.alloc(0);
        request.headers.set("Content-Length", '${content.length}');
        for (name => value in attributes) {
            request.setAttribute(name, value);
        }
        var context = new InternalContext(request, content, limit);
        request.context = context;
        var outerRequest = RequestStatic.request();
        var outerResponse = ResponseStatic.get();
        try {
            HttpHandler.process(context);
        } catch (error:Dynamic) {
            restore(outerRequest, outerResponse);
            throw error;
        }
        restore(outerRequest, outerResponse);
        if (context.failure != null) {
            throw context.failure;
        }
        return {
            status: context.status,
            headers: context.headers,
            body: context.buffer.getBytes()
        };
    }

    static function restore(request:Null<Request>, response:Null<Response>):Void {
        if (request == null) {
            RequestStatic.reset();
        } else {
            RequestStatic.set(request);
        }
        if (response == null) {
            ResponseStatic.clear();
        } else {
            ResponseStatic.set(response);
        }
    }

    static function host():String {
        var outer = RequestStatic.request();
        return outer != null && outer.host != null ? outer.host : "127.0.0.1";
    }
}

@:access(hx.well.http.Response)
private class InternalContext implements IDriverContext {
    @:isVar public var input(get, null):Input;
    @:isVar public var output(get, null):Output;

    public var status:Int = 500;
    public var headers:Map<String, String> = [];
    public var buffer(default, null):BytesBuffer = new BytesBuffer();
    public var failure:Null<Exception>;

    final request:Request;
    final limit:Int;
    var started = false;

    public function new(request:Request, body:Bytes, limit:Int) {
        this.request = request;
        this.limit = limit;
        input = new BytesInput(body);
        output = new LimitedOutput(this);
    }

    public function get_input():Input {
        return input;
    }

    public function get_output():Output {
        return output;
    }

    private function buildRequest():Request {
        return request;
    }

    private function parseBody():Void {
        SocketRequestParser.parseBody(request, input);
    }

    public function writeResponse(response:Response):Void {
        if (response == null) {
            return;
        }
        var shared = ResponseStatic.get();
        status = response.statusCode ?? shared?.statusCode ?? 200;
        headers = [];
        collect(response);
        if (shared != null) {
            collect(shared);
        }
        var source = response.toInput();
        try {
            var chunk = Bytes.alloc(65536);
            while (true) {
                var size = source.readBytes(chunk, 0, chunk.length);
                if (size <= 0) {
                    break;
                }
                append(chunk, 0, size);
            }
        } catch (_:Eof) {} catch (error:Exception) {
            failure = error;
        }
        try {
            source.close();
        } catch (_:Dynamic) {}
        if (response.after != null) {
            response.after();
        }
    }

    /**
        Adds the headers of `response` that are not set yet. Handlers may set
        header values from untyped data, such as numbers, so each value is
        read untyped and written as text.
    **/
    function collect(response:Response):Void {
        var values:Map<String, Dynamic> = cast response.headers;
        for (name in values.keys()) {
            if (!headers.exists(name)) {
                headers.set(name, Std.string(values.get(name)));
            }
        }
    }

    public function append(bytes:Bytes, position:Int, length:Int):Void {
        if (buffer.length + length > limit) {
            throw new Exception("The CMS response exceeds its size limit.");
        }
        buffer.addBytes(bytes, position, length);
    }

    public function beginWrite():Void {
        if (started) {
            return;
        }
        started = true;
        var shared = ResponseStatic.get();
        status = shared?.statusCode ?? 200;
        headers = [];
        if (shared != null) {
            collect(shared);
        }
    }

    public function writeInput(i:Input, ?bufsize:Int):Void {
        beginWrite();
        output.writeInput(i, bufsize);
    }

    public function writeString(s:String, ?encoding:Encoding):Void {
        beginWrite();
        output.writeString(s, encoding);
    }

    public function writeFullBytes(bytes:Bytes, pos:Int = 0, len:Int = -1):Void {
        beginWrite();
        output.writeFullBytes(bytes, pos, len < 0 ? bytes.length - pos : len);
    }

    public function writeByte(c:Int):Void {
        beginWrite();
        output.writeByte(c);
    }

    public function flush():Void {}

    public function close():Void {}

    public function upgradeToWebSocket(request:Request, handler:AbstractWebSocketHandler):Void {
        throw new Exception("An in-process request cannot open a WebSocket.");
    }
}

/** Collects streamed response bytes up to the request's limit. **/
private class LimitedOutput extends Output {
    final context:InternalContext;

    public function new(context:InternalContext) {
        this.context = context;
    }

    override public function writeByte(c:Int):Void {
        var single = Bytes.alloc(1);
        single.set(0, c);
        context.append(single, 0, 1);
    }

    override public function writeBytes(s:Bytes, pos:Int, len:Int):Int {
        context.append(s, pos, len);
        return len;
    }
}
