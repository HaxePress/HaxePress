package hx.press.ai;

import haxe.Exception;
import haxe.io.Bytes;
import hx.press.CmsAccess;
import hx.press.themes.ThemeMcpHost;
import hx.well.database.Connection;
import hx.well.http.RequestStatic;
import hx.well.websocket.AbstractWebSocketHandler;
import hx.well.websocket.WebSocketSession;

class AdminMcpWebSocket extends AbstractWebSocketHandler {
    public function new() {
        super();
        AdminMcpSockets.register(this);
    }

    public function onOpen(socket:WebSocketSession):Void {
        var request = RequestStatic.request();
        try {
            var admin = CmsAccess.current();
            if (!ThemeMcpHost.available() || admin == null) {
                socket.close();
            } else {
                AdminMcpSockets.browser(socket, admin.id, request.session.sessionKey);
            }
        } catch (_:Dynamic) {
            socket.close();
        }
        Connection.free();
    }

    public function onMessage(socket:WebSocketSession, message:String):Void {
        var body = Bytes.ofString(message);
        if (body.length > ThemeMcpHost.MAX_REQUEST_BYTES) {
            socket.close();
            return;
        }
        try {
            var key = AdminMcpSockets.sessionKey(socket);
            if (AdminMcpAccess.browser(key) == null) {
                Connection.free();
                socket.close();
                return;
            }
            Connection.free();
            var headers = [
                "Accept" => "application/json, text/event-stream",
                "Content-Type" => "application/json",
                "X-Haxepress-Transport" => "websocket",
                AdminMcpAccess.BROWSER_HEADER => key
            ];
            var reply = ThemeMcpHost.exchangeAdmin(null, "", "POST", body, headers);
            if (reply.status >= 500) {
                socket.close();
            } else if (reply.status != 202 && reply.status != 204 && reply.body.length > 0) {
                socket.send(reply.body.toString());
            }
        } catch (_:Dynamic) {
            Connection.free();
            socket.close();
        }
    }

    public function onBinary(socket:WebSocketSession, data:Bytes):Void {
        socket.close();
    }

    public function onClose(socket:WebSocketSession, code:Int, reason:String):Void {}

    public function onError(socket:WebSocketSession, error:Exception):Void {
        socket.close();
    }
}
