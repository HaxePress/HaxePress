package hx.press.themes;

import haxe.io.BytesInput;
import haxe.Int64;
import haxe.Json;
import hx.press.themes.ThemeAiAccess.ThemeAiActor;
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

    public static function endpoint(request:Request):AbstractResponse {
        if (request.bodyBytes != null && request.bodyBytes.length > ThemeMcpHost.MAX_REQUEST_BYTES) {
            return ResponseBuilder.asJson({error: "The MCP request exceeds its size limit."}, 413);
        }
        var headers:Map<String, String> = [];
        for (name in requestHeaders) {
            var value = request.header(name);
            if (value != null) {
                headers.set(name, value);
            }
        }
        var actor:ThemeAiActor = request.getAttribute(ThemeAiAccess.ACTOR);
        headers.set("X-Haxepress-Permissions", Json.stringify(actor.permissions));
        try {
            var reply = ThemeMcpHost.exchange(request.route("id"),
                request.header("Authorization"), request.method,
                request.method == "POST" ? request.bodyBytes : null, headers);
            var response = ResponseBuilder.asInput(new BytesInput(reply.body),
                Int64.ofInt(reply.body.length), reply.status);
            for (name => value in reply.headers) {
                response.header(name, value);
            }
            return response.header("Cache-Control", "private, no-store");
        } catch (_:Dynamic) {
            return ResponseBuilder.asJson({error: "The site MCP service is unavailable."}, 503);
        }
    }
}
