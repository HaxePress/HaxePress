package hx.press.themes;

import haxe.io.BytesInput;
import haxe.Int64;
import hx.press.themes.ThemeMcpHost.McpReply;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.ResponseBuilder;

class ThemeMcpController {
    public static final requestHeaders = [
        "Accept",
        "Content-Type",
        "MCP-Protocol-Version",
        "Mcp-Method",
        "Mcp-Name",
        "Mcp-Session-Id"
    ];

    public static function forwardHeaders(request:Request):Map<String, String> {
        var headers:Map<String, String> = [];
        for (name in requestHeaders) {
            var value = request.header(name);
            if (value != null) {
                headers.set(name, value);
            }
        }
        return headers;
    }

    public static function respond(reply:McpReply):AbstractResponse {
        var response = ResponseBuilder.asInput(new BytesInput(reply.body),
            Int64.ofInt(reply.body.length), reply.status);
        for (name => value in reply.headers) {
            response.header(name, value);
        }
        return response.header("Cache-Control", "private, no-store");
    }
}
