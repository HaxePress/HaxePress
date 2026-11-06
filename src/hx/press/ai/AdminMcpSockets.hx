package hx.press.ai;

import haxe.Json;
import hx.well.websocket.AbstractWebSocketHandler;
import hx.well.websocket.WebSocketSession;

class AdminMcpSockets {
    static var browserHandler:AbstractWebSocketHandler;
    static inline var OWNER = "adminMcpOwner";
    static inline var BROWSER = "adminMcpBrowser";

    public static function register(handler:AbstractWebSocketHandler):Void {
        browserHandler = handler;
    }

    public static function browser(socket:WebSocketSession, adminId:Int, sessionKey:String):Void {
        socket.setAttribute(OWNER, adminId);
        socket.setAttribute(BROWSER, sessionKey);
    }

    public static function sessionKey(socket:WebSocketSession):String {
        return socket.getAttribute(BROWSER);
    }

    public static function changed(adminId:Int):Void {
        if (browserHandler == null) {
            return;
        }
        var notice = Json.stringify({
            jsonrpc: "2.0",
            method: "notifications/haxepress/admin_ai_changed"
        });
        for (socket in browserHandler.getSessions()) {
            if (socket.getAttribute(OWNER) == adminId) {
                if (AdminMcpAccess.browser(sessionKey(socket)) != null) {
                    socket.send(notice);
                } else {
                    socket.close();
                }
            }
        }
    }
}
