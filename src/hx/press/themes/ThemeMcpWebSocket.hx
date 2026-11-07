package hx.press.themes;

import haxe.Exception;
import haxe.Json;
import haxe.io.Bytes;
import hx.press.CmsAccess;
import hx.press.mcp.McpEndpoint;
import hx.well.database.Connection;
import hx.well.http.Request;
import hx.well.http.RequestStatic;
import hx.well.http.Response;
import hx.well.websocket.AbstractWebSocketHandler;
import hx.well.websocket.WebSocketSession;

/** The signed-in editor keeps its local tools and receives live draft revisions. */
class ThemeMcpWebSocket extends AbstractWebSocketHandler {
    public function new() {
        super();
    }

    public function onOpen(session:WebSocketSession):Void {
        var request = RequestStatic.request();
        var themeId = request.route("id");
        session.setAttribute("theme", themeId);
        try {
            if (!CmsAccess.can("extensions")) {
                Connection.free();
                session.close();
                return;
            }
            var sessionKey = request.session.sessionKey;
            session.setAttribute("browser", sessionKey);
            var authorization = ThemeAiAccess.browserCredential(themeId, sessionKey);
            session.setAttribute("authorization", authorization);
            var actor = ThemeAiAccess.authenticateToken(themeId, authorization);
            if (actor == null) {
                session.close();
            } else {
                session.setAttribute("permissions", Json.stringify(actor.permissions));
                ThemeCollaboration.attach(themeId, authorization, actor, session, this);
            }
        } catch (error:Dynamic) {
            Connection.free();
            session.close();
            throw error;
        }
        Connection.free();
    }

    public function onMessage(session:WebSocketSession, message:String):Void {
        if (Bytes.ofString(message).length > McpEndpoint.MAX_REQUEST_BYTES) {
            session.close();
            return;
        }
        var themeId:String = session.getAttribute("theme");
        var authorization:String = session.getAttribute("authorization");
        var sessionKey:String = session.getAttribute("browser");
        try {
            var actor = ThemeAiAccess.authenticateToken(themeId, authorization);
            if (actor == null) {
                Connection.free();
                session.close();
                return;
            }
            var permissions = Json.stringify(actor.permissions);
            if (session.getAttribute("permissions") != permissions) {
                session.setAttribute("permissions", permissions);
                session.send(Json.stringify({
                    jsonrpc: "2.0",
                    method: "notifications/haxepress/permissions",
                    params: {themeId: themeId, permissions: actor.permissions}
                }));
            }
            var reply = ThemeMcpController.message(themeId, sessionKey, message);
            Connection.free();
            if (reply.status >= 400 && reply.body == null) {
                session.close();
            } else if (reply.status >= 500) {
                session.close();
            } else if (reply.body != null) {
                session.send(reply.body);
            }
        } catch (_:Dynamic) {
            Connection.free();
            session.close();
        }
    }

    /** One message of an editor that cannot open a WebSocket, answered over HTTP. **/
    override public function onPost(request:Request):Null<Response> {
        return ThemeMcpController.post(request);
    }

    public function onBinary(session:WebSocketSession, data:Bytes):Void {
        session.close();
    }

    public function onClose(session:WebSocketSession, code:Int, reason:String):Void {
        var themeId:String = session.getAttribute("theme");
        var authorization:String = session.getAttribute("authorization");
        session.setAttribute("authorization", null);
        try {
            ThemeAiAccess.forgetBrowserCredential(authorization);
            ThemeCollaboration.detach(themeId, session.id);
        } catch (error:Dynamic) {
            Connection.free();
            throw error;
        }
        Connection.free();
    }

    public function onError(session:WebSocketSession, error:Exception):Void {
        session.close();
    }
}
