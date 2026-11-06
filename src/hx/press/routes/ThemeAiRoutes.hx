package hx.press.routes;

import hx.press.handler.admin.packages.SaveAiThemeDesignHandler;
import hx.press.middleware.ThemeAiMiddleware;
import hx.press.themes.ThemeAiController;
import hx.press.themes.ThemeAssetController;
import hx.press.handler.admin.packages.UploadThemeImageHandler;
import hx.well.route.Route;
import hx.press.middleware.ThemeMcpMiddleware;
import hx.press.themes.ThemeMcpController;
import hx.press.themes.ThemeMcpWebSocket;

using hx.well.tools.RouteElementTools;

class ThemeAiRoutes {
    public static function register():Void {
        Route.path("/mcp/themes/{id}").middleware([ThemeMcpMiddleware]).group(() -> {
            Route.post("", ThemeMcpController.endpoint).attribute("inertia.share", false);
            Route.get("", ThemeMcpController.endpoint).attribute("inertia.share", false);
            Route.delete("", ThemeMcpController.endpoint).attribute("inertia.share", false);
            Route.websocket("/ws")
                .handler(new ThemeMcpWebSocket())
                .attribute("inertia.share", false);
        });
        Route.path("/api/theme-designer/{id}").middleware([ThemeAiMiddleware]).group(() -> {
            Route.get("/design", ThemeAiController.read).attribute("inertia.share", false);
            Route.post("/design", new SaveAiThemeDesignHandler()).attribute("inertia.share", false);
            Route.get("/assets", ThemeAssetController.listing).attribute("inertia.share", false);
            Route.post("/assets", new UploadThemeImageHandler(true))
                .attribute("inertia.share", false);
            Route.post("/assets/verify", new UploadThemeImageHandler(true, true))
                .attribute("inertia.share", false);
            Route.get("/assets/{asset}", ThemeAssetController.readForAi)
                .whereNumber("asset")
                .attribute("inertia.share", false);
            Route.get("/media", ThemeAiController.media).attribute("inertia.share", false);
            Route.get("/collections/{key}", ThemeAiController.collection)
                .attribute("inertia.share", false);
            Route.get("/media/{media}", ThemeAiController.image)
                .whereNumber("media")
                .attribute("inertia.share", false);
        });
    }
}
