package hx.press.install;

import hx.press.handler.install.CheckDatabaseHandler;
import hx.press.handler.install.FinishInstallationHandler;
import hx.press.handler.install.ReviewInstallationHandler;
import hx.press.middleware.AdminSessionMiddleware;
import hx.well.middleware.CsrfMiddleware;
import hx.well.middleware.SessionMiddleware;
import hx.well.middleware.AbstractMiddleware;
import hx.well.route.Route;
#if jvm
import hx.press.backup.BackupUploads;
import hx.press.backup.BackupUploads.BackupUploadPurpose;
import hx.press.backup.SiteBackup;
#end

using hx.well.tools.RouteElementTools;

class InstallationRoutes {
    public static function register():Void {
        var middlewares:Array<Class<AbstractMiddleware>> = [
            InstallationAccessMiddleware,
            SessionMiddleware,
            AdminSessionMiddleware,
            CsrfMiddleware
        ];
        Route.path("/admin/install").middleware(middlewares).group(() -> {
            Route.get("", InstallationController.page);
            Route.post("/database", new CheckDatabaseHandler());
            Route.post("/administrator", new ReviewInstallationHandler());
            Route.post("/finish", new FinishInstallationHandler());
            #if jvm
            Route.post("/restore", SiteBackup.restore);
            BackupUploads.register("/restore/uploads", BackupUploadPurpose.Restore);
            #end
        });
    }
}
