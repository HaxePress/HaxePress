package hx.press.themes;

import haxe.Exception;
import haxe.Json;
import haxe.io.Bytes;
import hx.press.CmsAccess;
import hx.well.database.Connection;
import hx.well.http.RequestStatic;
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
            if (!ThemeMcpHost.available() || !CmsAccess.can("extensions")) {
                Connection.free();
                session.close();
                return;
            }
            var authorization = ThemeAiAccess.browserCredential(themeId,
                request.session.sessionKey);
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
        var body = Bytes.ofString(message);
        if (body.length > ThemeMcpHost.MAX_REQUEST_BYTES) {
            session.close();
            return;
        }
        var themeId:String = session.getAttribute("theme");
        var authorization:String = session.getAttribute("authorization");
        try {
            var actor = ThemeAiAccess.authenticateToken(themeId, authorization);
            Connection.free();
            if (actor == null) {
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
            var headers = [
                "Accept" => "application/json, text/event-stream",
                "Content-Type" => "application/json",
                "X-Haxepress-Transport" => "websocket",
                "X-Haxepress-Permissions" => permissions
            ];
            var reply = ThemeMcpHost.exchange(themeId, authorization, "POST", body, headers);
            if (reply.status == 202 || reply.status == 204) {
                return;
            }
            if (reply.body.length > 0 && reply.status < 500) {
                session.send(reply.body.toString());
            } else {
                session.close();
            }
        } catch (_:Dynamic) {
            Connection.free();
            session.close();
        }
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
