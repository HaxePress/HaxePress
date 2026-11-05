package hx.press.install;

import hx.press.install.InstallationDatabase.SetupDatabase;
import hx.well.facades.Inertia;
import hx.well.http.Request;
import hx.well.http.Response;
import hx.well.middleware.CsrfMiddleware;

class InstallationController {
    public static function locked(request:Request):Response {
        var props = {
            setup: {
                blocked: true,
                message: InstallationState.blockedReason(),
                database: null
            }
        };
        return Inertia.render("Admin/Install", props)
            .status(403)
            .header("Cache-Control", "private, no-store");
    }

    public static function page(request:Request):Response {
        var database:Null<SetupDatabase> = request.session.get(InstallationDatabase.SESSION_KEY);
        var verified = database != null
            && Date.now()
                .getTime() - database.checkedAt < InstallationDatabase.VERIFICATION_LIFETIME;
        var props = {
            setup: {
                blocked: false,
                message: "",
                database: verified ? InstallationDatabase.summary(database) : null
            },
            csrfToken: request.session.get(CsrfMiddleware.TOKEN_KEY)
        };
        return Inertia.render("Admin/Install", props).header("Cache-Control", "private, no-store");
    }
}
