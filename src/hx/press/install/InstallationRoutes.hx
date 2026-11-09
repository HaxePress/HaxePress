package hx.press.install;

import hx.press.handler.install.CheckDatabaseHandler;
import hx.press.handler.install.FinishInstallationHandler;
import hx.press.handler.install.ReviewInstallationHandler;
import hx.press.handler.install.UnlockInstallationHandler;
import hx.press.middleware.AdminSessionMiddleware;
import hx.well.middleware.CsrfMiddleware;
import hx.well.middleware.SessionMiddleware;
import hx.well.middleware.AbstractMiddleware;
import hx.well.route.Route;

using hx.well.tools.RouteElementTools;

class InstallationRoutes {
    /** Access, session and CSRF checks of every installation route. **/
    public static function middlewares():Array<Class<AbstractMiddleware>> {
        return [
            InstallationAccessMiddleware,
            SessionMiddleware,
            AdminSessionMiddleware,
            CsrfMiddleware
        ];
    }

    public static function register():Void {
        // Entering the setup key needs no session: it is how a locked browser gets in.
        Route.post("/admin/install/unlock", new UnlockInstallationHandler());
        Route.path("/admin/install").middleware(middlewares()).group(() -> {
            Route.get("", InstallationController.page);
            Route.post("/database", new CheckDatabaseHandler());
            Route.post("/administrator", new ReviewInstallationHandler());
            Route.post("/finish", new FinishInstallationHandler());
        });
    }
}
