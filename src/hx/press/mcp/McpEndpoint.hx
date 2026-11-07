package hx.press.mcp;

import haxe.Json;
import haxe.crypto.Base64;
import haxe.io.Bytes;
import hx.press.mcp.McpServer.McpEra;
import hx.press.mcp.McpServer.McpError;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.Response;
import hx.well.http.ResponseBuilder;

/** The outcome of one transport message: an HTTP status and an optional JSON body. **/
typedef McpExchange = {
    var status:Int;
    var body:Null<String>;
}

/**
    Streamable HTTP for MCP, served by the site's own routes. Every POST
    carries one JSON-RPC message (or a batch of 2025-revision messages) and
    is answered with `application/json`; the server keeps no state between
    requests, so any process can answer any request. The server has no
    stream to offer, so GET and DELETE answer 405.
**/
class McpEndpoint {
    public static inline var MAX_REQUEST_BYTES = 8 * 1048576;
    public static inline var MAX_RESPONSE_BYTES = 10 * 1048576;

    /**
        Serves an HTTP request. `build` creates the connection's server once
        the message is known to be valid; `served` runs after a successful
        exchange.
    **/
    public static function http(request:Request, build:Void->McpServer,
            ?served:Void->Void):AbstractResponse {
        if (request.method != "POST") {
            return error(405, null, -32000, "Method not allowed.").header("Allow", "POST");
        }
        var contentType = request.header("Content-Type", "").toLowerCase();
        if (contentType.indexOf("application/json") < 0) {
            return error(415, null, -32000,
                "Unsupported Media Type: Content-Type must be application/json");
        }
        var accept = request.header("Accept", "*/*").toLowerCase();
        if (accept.indexOf("application/json") < 0
            && accept.indexOf("*/*") < 0
            && accept.indexOf("application/*") < 0
            && accept.indexOf("text/event-stream") < 0) {
            return error(406, null, -32000, "Not Acceptable: Client must accept application/json");
        }
        var body = request.bodyBytes ?? Bytes.alloc(0);
        if (body.length > MAX_REQUEST_BYTES) {
            return error(413, null, -32000, "The MCP request exceeds its size limit.");
        }
        var headers = {
            version: request.header("MCP-Protocol-Version"),
            method: request.header("Mcp-Method"),
            name: request.header("Mcp-Name")
        };
        var exchange = exchange(body.toString(), build, headers);
        if (exchange.status >= 200 && exchange.status < 300 && served != null) {
            served();
        }
        return respond(exchange);
    }

    /**
        Serves one message of a browser connection, a WebSocket frame or its
        HTTP fallback. A frame has no HTTP headers, so the message's own
        metadata stands for them. Returns `null` when there is nothing to
        send back.
    **/
    public static function message(source:String, build:Void->McpServer):McpExchange {
        if (Bytes.ofString(source).length > MAX_REQUEST_BYTES) {
            return {status: 413, body: null};
        }
        return exchange(source, build, null);
    }

    public static function respond(exchange:McpExchange):Response {
        if (exchange.body == null) {
            return ResponseBuilder.asString("", exchange.status)
                .header("Cache-Control", "private, no-store");
        }
        return ResponseBuilder.asString(exchange.body, exchange.status)
            .header("Content-Type", "application/json")
            .header("Cache-Control", "private, no-store");
    }

    static function exchange(source:String, build:Void->McpServer,
            headers:Null<{version:Null<String>, method:Null<String>, name:Null<String>}>):McpExchange {
        var parsed:Dynamic;
        try {
            parsed = Json.parse(source);
        } catch (_:Dynamic) {
            return failure(400, null, McpError.PARSE_ERROR, "Parse error: Invalid JSON");
        }
        var server:Null<McpServer> = null;
        function connection():McpServer {
            if (server == null) {
                server = build();
            }
            return server;
        }
        if (Std.isOfType(parsed, Array)) {
            var messages:Array<Dynamic> = parsed;
            var replies:Array<Dynamic> = [];
            for (entry in messages) {
                if (!valid(entry)) {
                    replies.push(McpServer.failure(null,
                        new McpError(McpError.INVALID_REQUEST, "Invalid Request")));
                    continue;
                }
                var reply = connection().handle(entry, Legacy);
                if (reply != null) {
                    replies.push(reply);
                }
            }
            return replies.length == 0 ? {status: 202, body: null} : {
                status: 200,
                body: Json.stringify(replies)
            };
        }
        if (!valid(parsed)) {
            return failure(400, null, McpError.INVALID_REQUEST,
                "Bad Request: the request body is not a valid JSON-RPC message");
        }
        var id:Dynamic = Reflect.field(parsed, "id");
        var era:McpEra;
        try {
            era = McpServer.era(parsed);
            if (headers != null) {
                crossCheck(parsed, era, headers);
            }
        } catch (error:McpError) {
            return {status: error.status, body: Json.stringify(McpServer.failure(id, error))};
        }
        var reply:Null<Dynamic>;
        try {
            reply = connection().handle(parsed, era);
        } catch (error:McpError) {
            return {status: error.status, body: Json.stringify(McpServer.failure(id, error))};
        }
        if (reply == null) {
            return {status: 202, body: null};
        }
        var status = 200;
        if (reply.error != null && reply.error.code == McpError.METHOD_NOT_FOUND && era != Legacy) {
            status = 404;
        }
        return {status: status, body: Json.stringify(reply)};
    }

    static function valid(message:Dynamic):Bool {
        if (!McpSchema.isObject(message) || message.jsonrpc != "2.0") {
            return false;
        }
        var hasMethod = Std.isOfType(message.method, String);
        var isResponse = Reflect.hasField(message, "id")
            && (Reflect.hasField(message, "result") || Reflect.hasField(message, "error"));
        return hasMethod || isResponse;
    }

    /**
        Under the 2026-07-28 revision the HTTP headers repeat the protocol
        version, the method and the tool, prompt or resource name of the
        body; requests whose headers and body disagree are refused.
    **/
    static function crossCheck(message:Dynamic, era:McpEra,
            headers:{version:Null<String>, method:Null<String>, name:Null<String>}):Void {
        var revision = switch (era) {
            case Modern(value): value;
            case Legacy: return;
        };
        if (headers.version == null) {
            mismatch("(missing)",
                'the body envelope names protocol version ${revision} but the required MCP-Protocol-Version header is absent');
        }
        if (StringTools.trim(headers.version) != revision) {
            mismatch(headers.version,
                'the body envelope names protocol version ${revision} but the MCP-Protocol-Version header names ${headers.version}');
        }
        var method:String = message.method;
        if (method == null) {
            return;
        }
        if (headers.method != null && StringTools.trim(headers.method) != method) {
            mismatch(headers.method,
                'the body names method ${method} but the Mcp-Method header names ${headers.method}');
        }
        var field = method == "resources/read" ? "uri" : "name";
        var named:Dynamic = message.params == null ? null : Reflect.field(message.params, field);
        if (headers.name != null && Std.isOfType(named, String)) {
            var header = decodeName(StringTools.trim(headers.name));
            if (header != named) {
                mismatch(headers.name,
                    'the body carries params.${field}="${named}" but the Mcp-Name header names "${header}"');
            }
        }
    }

    /** Header values may be RFC 2047-style Base64 words for names outside ASCII. **/
    static function decodeName(value:String):String {
        var encoded = ~/^=\?base64\?([A-Za-z0-9+\/=]*)\?=$/;
        if (!encoded.match(value)) {
            return value;
        }
        try {
            return Base64.decode(encoded.matched(1)).toString();
        } catch (_:Dynamic) {
            return value;
        }
    }

    static function mismatch(header:String, detail:String):Void {
        var data = {mismatch: {header: header, body: detail}};
        throw new McpError(McpError.HEADER_MISMATCH,
            'Bad Request: the request headers and body disagree: ${detail}', data, 400);
    }

    static function failure(status:Int, id:Dynamic, code:Int, message:String):McpExchange {
        var reply = McpServer.failure(id, new McpError(code, message));
        return {status: status, body: Json.stringify(reply)};
    }

    static function error(status:Int, id:Dynamic, code:Int, message:String):Response {
        return respond(failure(status, id, code, message));
    }
}
