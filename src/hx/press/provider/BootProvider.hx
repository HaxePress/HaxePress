package hx.press.provider;

import hx.press.AdminController;
import hx.well.provider.AbstractProvider;
import hx.well.route.Route;
import hx.press.SiteController;
import hx.press.handler.ChangeLocaleHandler;
import hx.press.handler.ValidationErrorHandler;
import hx.press.validation.CmsValidators;
import hx.press.CmsController;
import hx.press.handler.ExtensionAssetHandler;
import hx.press.packages.PackageManager;
import hx.press.routes.AdminRoutes;
import hx.press.routes.AdminMcpRoutes;
import hx.press.routes.ThemeAiRoutes;
import hx.press.routes.LegacyContentRoutes;
import hx.press.handler.CategoryOptionsHandler;
import hx.press.handler.MediaImageHandler;
import hx.press.handler.SitePublicHandler;
import hx.press.themes.ThemeAssetController;
import hx.press.install.InstallationState;
import hx.press.install.InstallationRoutes;
import hx.press.view.Pages;
import hx.press.view.View;
import hx.press.view.WelloutClient;
import hx.press.view.Translations;
#if jvm
import hx.press.install.InstallationPlugins;
#end
import hx.press.view.DesignViews;

using hx.well.tools.RouteElementTools;

class BootProvider extends AbstractProvider {
    public function boot():Void {
        CmsValidators.register();
        // Plugins render pages through Pages, which has no dependency on the renderer.
        Pages.renderer = (name, props) -> View.render(name, props);
        Pages.viewRenderer = (name, props) -> View.renderPlugin(name, props);
        Pages.validationRedirects = request -> View.redirectsValidation(request);
        Pages.validationRedirector = (request, scope, message,
            url) -> AdminController.validationRedirect(request, scope, message, url);
        InstallationRoutes.register();
        Route.get("/", SiteController.home);
        Route.publicHandler = new SitePublicHandler();
        LegacyContentRoutes.register();
        Route.post("/locale", new ChangeLocaleHandler());
        Route.get("/tags/{slug}", CmsController.tagArchive);
        Route.get("/categories/options", new CategoryOptionsHandler());
        Route.get("/about", SiteController.about);
        Route.get("/_wellout/{file}", WelloutClient.serve);
        Route.get("/_translations/{file}", Translations.serve);
        Route.get("/theme-design/{file}", DesignViews.serveStylesheet);
        Route.get("/media/{filename}", new MediaImageHandler());
        Route.get("/theme-assets/{id}/{filename}", ThemeAssetController.image);
        Route.get("/extension-assets/{id}/{generation}/{asset}", new ExtensionAssetHandler())
            .where("asset", ".+");
        Route.path("/admin").group(AdminRoutes);
        AdminMcpRoutes.remote();
        ThemeAiRoutes.register();
        Route.status(404).handle(SiteController.notFound);
        Route.status(422).handler(new ValidationErrorHandler());
        if (!InstallationState.pending) {
            SiteRuntime.start();
        } else {
            #if jvm
            InstallationPlugins.start();
            #end
        }
    }
}
