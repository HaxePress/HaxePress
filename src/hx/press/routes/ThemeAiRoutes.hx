package hx.press.routes;

import hx.press.handler.admin.packages.SaveAiThemeDesignHandler;
import hx.press.middleware.ThemeAiMiddleware;
import hx.press.themes.ThemeAiController;
import hx.press.themes.ThemeAssetController;
import hx.press.handler.admin.packages.UploadThemeImageHandler;
import hx.well.route.Route;

using hx.well.tools.RouteElementTools;

class ThemeAiRoutes {
    public static function register():Void {
        Route.path("/api/theme-designer/{id}").middleware([ThemeAiMiddleware]).group(() -> {
            Route.get("/design", ThemeAiController.read);
            Route.post("/design", new SaveAiThemeDesignHandler());
            Route.get("/assets", ThemeAssetController.listing);
            Route.post("/assets", new UploadThemeImageHandler(true));
            Route.post("/assets/verify", new UploadThemeImageHandler(true, true));
            Route.get("/assets/{asset}", ThemeAssetController.readForAi).whereNumber("asset");
            Route.get("/media", ThemeAiController.media);
            Route.get("/collections/{key}", ThemeAiController.collection);
            Route.get("/media/{media}", ThemeAiController.image).whereNumber("media");
        });
    }
}
