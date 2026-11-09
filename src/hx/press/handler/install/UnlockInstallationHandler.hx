package hx.press.handler.install;

import hx.press.install.InstallationController;
import hx.press.install.InstallationKey;
import hx.press.install.InstallationState;
import hx.well.facades.Environment;
import hx.well.handler.AbstractHandler;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.ResponseBuilder;
import hx.well.http.ResponseStatic;

/**
    Opens the installer for a browser that enters the setup key. It runs
    without a session, like the locked page, and remembers the key in a
    cookie of the installer's path for two hours.
**/
class UnlockInstallationHandler extends AbstractHandler {
    public function execute(request:Request):AbstractResponse {
        if (!InstallationState.pending) {
            return ResponseBuilder.asString("Not Found", 404);
        }
        if (!InstallationKey.allowAttempt(request)) {
            return InstallationController.locked(request,
                "Too many setup keys were tried. Wait a minute and try again.", 429);
        }
        var input:Dynamic = request.input("key", "");
        var key = Std.isOfType(input, String) ? (input : String) : "";
        if (key.length > 200 || !InstallationKey.matches(key)) {
            return InstallationController.locked(request, "This is not the setup key.", 403);
        }
        ResponseStatic.get()
            .cookie(InstallationKey.COOKIE, InstallationKey.token())
            .path("/admin/install")
            .httpOnly(true)
            .sameSite("Strict")
            .secure(Environment.env("APP_ENV", "production") != "development")
            .maxAge(7200);
        return ResponseBuilder.asRedirect("/admin/install", 303)
            .header("Cache-Control", "private, no-store");
    }
}
