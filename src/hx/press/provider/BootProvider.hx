package hx.press.provider;

import hx.well.provider.AbstractProvider;
import hx.well.facades.Inertia;
import hx.well.route.Route;
import hx.press.SiteController;
import hx.press.handler.ChangeLocaleHandler;
import hx.press.handler.ValidationErrorHandler;
import hx.press.validation.CmsValidators;
import hx.press.CmsController;
import hx.press.handler.ExtensionAssetHandler;
import hx.press.packages.PackageManager;
import hx.press.routes.AdminRoutes;
import hx.press.routes.ThemeAiRoutes;
import hx.press.routes.LegacyContentRoutes;
import hx.press.handler.CategoryOptionsHandler;
import hx.press.handler.MediaImageHandler;
import hx.press.handler.SitePublicHandler;
import hx.press.themes.ThemeAssetController;
import hx.press.install.InstallationState;
import hx.press.install.InstallationRoutes;

using hx.well.tools.RouteElementTools;

class BootProvider extends AbstractProvider {
    public function boot():Void {
        CmsValidators.register();
        Inertia.setRootView("app");
        Inertia.resolveUrlUsing(request -> {
            var pairs = [
                for (key => value in request.queries)
                    '${StringTools.urlEncode(key)}=${StringTools.urlEncode(value)}'
            ];
            var query = pairs.length == 0 ? "" : '?${pairs.join("&")}';
            return '${request.path}${query}';
        });
        InstallationRoutes.register();
        Route.get("/", SiteController.home);
        Route.publicHandler = new SitePublicHandler();
        LegacyContentRoutes.register();
        Route.post("/locale", new ChangeLocaleHandler()).attribute("inertia.share", false);
        Route.get("/tags/{slug}", CmsController.tagArchive);
        Route.get("/categories/options", new CategoryOptionsHandler());
        Route.get("/about", SiteController.about);
        Route.get("/media/{filename}", new MediaImageHandler());
        Route.get("/theme-assets/{id}/{filename}", ThemeAssetController.image);
        Route.get("/extension-assets/{id}/{generation}/{asset}", new ExtensionAssetHandler())
            .where("asset", ".+");
        Route.path("/admin").group(AdminRoutes);
        ThemeAiRoutes.register();
        Route.status(404).handle(SiteController.notFound);
        Route.status(422).handler(new ValidationErrorHandler());
        if (!InstallationState.pending) {
            SiteRuntime.start();
        }
    }
}
