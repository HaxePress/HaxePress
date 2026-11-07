package hx.press.ai;

import haxe.Exception;
import haxe.io.Bytes;
import hx.press.CmsAccess;
import hx.press.mcp.McpEndpoint;
import hx.well.database.Connection;
import hx.well.http.Request;
import hx.well.http.RequestStatic;
import hx.well.http.Response;
import hx.well.websocket.AbstractWebSocketHandler;
import hx.well.websocket.WebSocketSession;

/**
    The signed-in admin page's MCP connection. Browsers send JSON-RPC
    messages over a WebSocket, which also delivers change notices; where
    the site runs without WebSockets (PHP), the page posts each message to
    the same address and polls for changes instead.
**/
class AdminMcpWebSocket extends AbstractWebSocketHandler {
    public function new() {
        super();
        AdminMcpSockets.register(this);
    }

    public function onOpen(socket:WebSocketSession):Void {
        var request = RequestStatic.request();
        try {
            var admin = CmsAccess.current();
            if (admin == null) {
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
        if (Bytes.ofString(message).length > McpEndpoint.MAX_REQUEST_BYTES) {
            socket.close();
            return;
        }
        try {
            var grant = AdminMcpAccess.browserGrant(AdminMcpSockets.sessionKey(socket));
            if (grant == null) {
                Connection.free();
                socket.close();
                return;
            }
            var reply = McpEndpoint.message(message, () -> AdminMcpServer.create(grant));
            Connection.free();
            if (reply.status >= 500) {
                socket.close();
            } else if (reply.body != null) {
                socket.send(reply.body);
            }
        } catch (_:Dynamic) {
            Connection.free();
            socket.close();
        }
    }

    /** One message of a browser that cannot open a WebSocket, answered over HTTP. **/
    override public function onPost(request:Request):Null<Response> {
        var grant = AdminMcpAccess.browserGrant(request.session.sessionKey);
        if (grant == null) {
            return McpEndpoint.respond({status: 401, body: null});
        }
        var body = request.bodyBytes ?? Bytes.alloc(0);
        return McpEndpoint.respond(McpEndpoint.message(body.toString(),
            () -> AdminMcpServer.create(grant)));
    }

    public function onBinary(socket:WebSocketSession, data:Bytes):Void {
        socket.close();
    }

    public function onClose(socket:WebSocketSession, code:Int, reason:String):Void {}

    public function onError(socket:WebSocketSession, error:Exception):Void {
        socket.close();
    }
}
