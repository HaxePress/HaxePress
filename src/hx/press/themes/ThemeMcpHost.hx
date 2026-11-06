package hx.press.themes;

import haxe.Exception;
import haxe.Json;
import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import hx.press.ServerSettings;
import hx.well.facades.Environment;
import hx.well.facades.Storage;
import hx.well.internal.SecureToken;
#if jvm
import java.net.HttpURLConnection;
import java.net.URL;
import sys.io.Process;
import sys.thread.Lock;
import jvm.thread.VirtualThread;
#end

typedef McpReply = {
    var status:Int;
    var headers:Map<String, String>;
    var body:Bytes;
}

/** One loopback SDK host belongs to the JVM site's lifetime; no client-side runtime is needed. */
class ThemeMcpHost {
    public static inline var MAX_REQUEST_BYTES = 8 * 1048576;
    public static inline var MAX_RESPONSE_BYTES = 10 * 1048576;
    static var port = 0;
    static var secret = "";
    #if jvm
    static var process:Null<Process>;
    #end

    public static function start():Void {
        #if jvm
        if (process != null || Environment.env("MCP_HOST_ENABLED", "true") != "true") {
            return;
        }
        var disk = Storage.disk("public");
        if (!disk.fileExists("mcp/hosted.mjs")) {
            return;
        }
        var child:Process;
        try {
            child = new Process(Environment.env("NODE_BINARY", "node"),
                [disk.path("mcp/hosted.mjs")]);
        } catch (_:Dynamic) {
            trace("The site MCP service could not start. Check NODE_BINARY and the Node.js installation.");
            return;
        }
        process = child;
        secret = SecureToken.generate(32);
        try {
            child.stdin.writeString('${Json.stringify({
                secret: secret,
                origin: 'http://127.0.0.1:${ServerSettings.port}'
            })}\n');
            child.stdin.flush();
        } catch (_:Dynamic) {
            stop();
            return;
        }
        var ready = new Lock();
        var selected:Null<Int> = null;
        VirtualThread.create(() -> {
            try {
                var line = new StringBuf();
                while (line.length < 256) {
                    var value = child.stdout.readByte();
                    if (value == 10) {
                        break;
                    }
                    line.addChar(value);
                }
                var response:Dynamic = Json.parse(line.toString());
                if (Std.isOfType(response.port,
                    Int) && response.port > 0 && response.port <= 65535) {
                    selected = response.port;
                }
            } catch (_:Dynamic) {}
            ready.release();
        }).start();
        // Drain stderr so diagnostics cannot fill a pipe and stall the host.
        VirtualThread.create(() -> {
            try {
                while (true) {
                    child.stderr.readByte();
                }
            } catch (_:Dynamic) {}
        }).start();
        if (!ready.wait(5) || selected == null) {
            stop();
            return;
        }
        port = selected;
        #end
    }

    public static function available():Bool {
        #if jvm
        return process != null && port > 0 && process.exitCode(false) == null;
        #else
        return false;
        #end
    }

    public static function stop():Void {
        #if jvm
        var child = process;
        process = null;
        port = 0;
        secret = "";
        if (child != null) {
            try {
                child.kill();
            } catch (_:Dynamic) {}
            try {
                child.close();
            } catch (_:Dynamic) {}
        }
        #end
    }

    public static function exchange(themeId:String, authorization:String, method:String,
            body:Bytes, headers:Map<String, String>):McpReply {
        if (!available()) {
            throw new Exception("The site MCP service is unavailable.");
        }
        if (body != null && body.length > MAX_REQUEST_BYTES) {
            throw new Exception("The MCP request exceeds its size limit.");
        }
        #if jvm
        var address = 'http://127.0.0.1:${port}/themes/${StringTools.urlEncode(themeId)}';
        var connection:HttpURLConnection = cast new URL(address).openConnection();
        connection.setConnectTimeout(5000);
        connection.setReadTimeout(30000);
        connection.setInstanceFollowRedirects(false);
        connection.setRequestMethod(method);
        connection.setRequestProperty("X-Haxepress-Bridge", secret);
        connection.setRequestProperty("Authorization", authorization);
        for (name => value in headers) {
            connection.setRequestProperty(name, value);
        }
        try {
            if (body != null) {
                connection.setDoOutput(true);
                connection.setFixedLengthStreamingMode(body.length);
                var output = connection.getOutputStream();
                output.write(body.getData());
                output.close();
            }
            var status = connection.getResponseCode();
            var responseHeaders:Map<String, String> = [];
            for (name in ["Content-Type", "Allow", "MCP-Protocol-Version", "Mcp-Session-Id"]) {
                var value = connection.getHeaderField(name);
                if (value != null) {
                    responseHeaders.set(name, value);
                }
            }
            var input = status >= 400 ? connection.getErrorStream() : connection.getInputStream();
            var buffer = Bytes.alloc(8192);
            var response = new BytesBuffer();
            var length = 0;
            if (input != null) {
                var size = input.read(buffer.getData(), 0, buffer.length);
                while (size != -1) {
                    length += size;
                    if (length > MAX_RESPONSE_BYTES) {
                        throw new Exception("The MCP response exceeds its size limit.");
                    }
                    response.addBytes(buffer, 0, size);
                    size = input.read(buffer.getData(), 0, buffer.length);
                }
                input.close();
            }
            connection.disconnect();
            return {status: status, headers: responseHeaders, body: response.getBytes()};
        } catch (error:Dynamic) {
            connection.disconnect();
            throw error;
        }
        #else
        throw new Exception("The hosted MCP service requires the JVM target.");
        #end
    }
}
