package hx.press.routes;

import hx.press.ai.AdminMcpController;
import hx.press.ai.AdminMcpMedia;
import hx.press.ai.AdminMcpWebSocket;
import hx.press.middleware.AdminMcpBrowserMiddleware;
import hx.press.middleware.AdminMcpRemoteMiddleware;
import hx.well.route.Route;

using hx.well.tools.RouteElementTools;

class AdminMcpRoutes {
    public static function admin():Void {
        Route.path("/ai").group(() -> {
            Route.get("", AdminMcpController.state);
            Route.post("/sessions", AdminMcpController.issue);
            Route.delete("/sessions/{id}", AdminMcpController.end);
            Route.get("/routes", AdminMcpController.routes);
            Route.get("/media/{id}", AdminMcpMedia.image).whereNumber("id");
            Route.get("/media/{id}/info", AdminMcpMedia.info).whereNumber("id");
            Route.websocket("/ws")
                .middleware([AdminMcpBrowserMiddleware])
                .handler(new AdminMcpWebSocket());
        });
    }

    public static function remote():Void {
        Route.path("/mcp/sessions/{id}").middleware([AdminMcpRemoteMiddleware]).group(() -> {
            Route.post("", AdminMcpController.endpoint);
            Route.get("", AdminMcpController.endpoint);
            Route.delete("", AdminMcpController.endpoint);
        });
    }
}
