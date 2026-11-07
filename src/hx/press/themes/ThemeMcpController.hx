package hx.press.themes;

import haxe.io.Bytes;
import hx.press.ai.AdminMcpAccess;
import hx.press.mcp.McpEndpoint;
import hx.press.mcp.McpEndpoint.McpExchange;
import hx.well.http.Request;
import hx.well.http.Response;

/**
    The theme editor's own MCP connection: the scoped theme tools of one
    theme for the signed-in browser, with that admin's per-theme AI
    permissions. Messages arrive over the editor's WebSocket or, where the
    site runs without WebSockets, as HTTP posts to the same address.
**/
class ThemeMcpController {
    /** Answers one message of the browser session `sessionKey` for `themeId`. **/
    public static function message(themeId:String, sessionKey:String, source:String):McpExchange {
        var grant = AdminMcpAccess.browserGrant(sessionKey);
        var actor = grant == null ? null : ThemeAiAccess.authenticateBrowser(themeId, sessionKey);
        if (grant == null || actor == null) {
            return {status: 401, body: null};
        }
        return McpEndpoint.message(source,
            () -> ThemeMcpTools.themeServer(grant, themeId, actor.permissions));
    }

    /** The HTTP fallback of the editor's WebSocket. **/
    public static function post(request:Request):Response {
        var body = request.bodyBytes ?? Bytes.alloc(0);
        var reply = message(request.route("id"), request.session.sessionKey, body.toString());
        return McpEndpoint.respond(reply);
    }
}
