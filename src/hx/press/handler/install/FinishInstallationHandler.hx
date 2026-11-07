package hx.press.handler.install;

import haxe.Exception;
import hx.press.AdminController;
import hx.press.CategoryData;
import hx.press.config.DatabaseConfig;
import hx.press.install.InstallationController;
import hx.press.install.InstallationController.SetupAdministrator;
import hx.press.install.InstallationDatabase;
import hx.press.install.InstallationDatabase.SetupDatabase;
#if jvm
import hx.press.install.InstallationPlugins;
#end
import hx.press.install.InstallationEnv;
import hx.press.install.InstallationState;
import hx.press.model.Admin;
import hx.press.provider.DatabaseProvider;
import hx.press.provider.SiteRuntime;
import hx.press.validation.ValidationResponder;
import hx.press.view.View;
import hx.well.database.Connection;
import hx.well.facades.Config;
import hx.well.facades.Environment;
import hx.well.handler.AbstractHandler;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.RequestStatic.request;
import hx.well.http.RequestStatic.auth;
import hx.well.http.ResponseBuilder;

class FinishInstallationHandler extends AbstractHandler implements ValidationResponder {
    public override function validate():Bool {
        if (reviewed(request()) != null) {
            // The review step already checked these fields; only its option arrives here.
            var sample:Dynamic = request().input("sample_content", "0");
            return Std.isOfType(sample, String) && (sample == "0" || sample == "1");
        }
        return request().validate([
            "site_name" => [Required, String, Min(2), Max(100), Regex("^[^\\x00-\\x1f\\x7f]+$")],
            "admin_name" => [Required, String, Min(2), Max(100), Regex("^[^\\x00-\\x1f\\x7f]+$")],
            "admin_email" => [Required, String, Email, Max(254), Regex("^[^\\x00-\\x1f\\x7f]+$")],
            "admin_password" => [
                Required,
                String,
                Min(12),
                Custom("cms.byte_length", [72]),
                Regex("^[^\\x00-\\x1f\\x7f]+$")
            ],
            "confirm_password" => [Required, String, Min(1)],
            "sample_content" => [Required, String, Regex("^[01]$")]
        ]);
    }

    public function validationFailed(request:Request):AbstractResponse {
        return failed(request,
            "Check the site and administrator fields. Use a password between 12 and 72 bytes.",
            422, "administrator");
    }

    /**
        The administrator kept by the review step, when the installer form
        confirms it. Requests that send the administrator fields use those.
    **/
    static function reviewed(request:Request):Null<SetupAdministrator> {
        if (request.input("admin_password") != null || request.session == null) {
            return null;
        }
        return request.session.get(InstallationController.ADMINISTRATOR_KEY);
    }

    static function setupInputs(request:Request):Map<String, Dynamic> {
        var administrator = reviewed(request);
        if (administrator == null) {
            return request.only("site_name", "admin_name", "admin_email", "admin_password",
                "confirm_password", "sample_content");
        }
        var sample:Dynamic = request.input("sample_content", "0");
        return [
            "site_name" => administrator.site_name,
            "admin_name" => administrator.admin_name,
            "admin_email" => administrator.admin_email,
            "admin_password" => administrator.admin_password,
            "confirm_password" => administrator.admin_password,
            "sample_content" => sample
        ];
    }

    /** JSON for scripts; the installer form returns to `step` with the error. **/
    static function failed(request:Request, message:String, status:Int,
            step:String):AbstractResponse {
        var url = InstallationState.pending ? '/admin/install?step=${step}' : "/admin/login";
        var scope = InstallationState.pending ? "setup" : "credentials";
        var redirect = AdminController.validationRedirect(request, scope, message, url);
        if (redirect != null) {
            return redirect.header("Cache-Control", "private, no-store");
        }
        return ResponseBuilder.asJson({error: message}, status)
            .header("Cache-Control", "private, no-store");
    }

    public function execute(request:Request):AbstractResponse {
        var inputs = setupInputs(request);
        var siteName = StringTools.trim(inputs.get("site_name"));
        var adminName = StringTools.trim(inputs.get("admin_name"));
        if (siteName.length < 2 || adminName.length < 2) {
            return validationFailed(request);
        }
        if (inputs.get("admin_password") != inputs.get("confirm_password")) {
            return failed(request, "The passwords do not match.", 422, "administrator");
        }
        var database:Null<SetupDatabase> = request.session.get(InstallationDatabase.SESSION_KEY);
        if (database == null
            || Date.now()
                .getTime() - database.checkedAt >= InstallationDatabase.VERIFICATION_LIFETIME) {
            return failed(request, "Verify the database connection again before continuing.", 409,
                "database");
        }
        InstallationState.locks.acquire("installation");
        var prepared:Null<String> = null;
        var previous:Map<String, String> = [];
        var administrator:Map<String, String> = [
            "ADMIN_NAME" => adminName,
            "ADMIN_EMAIL" => CategoryData.key(inputs.get("admin_email")),
            "ADMIN_PASSWORD" => inputs.get("admin_password")
        ];
        var phase = "database verification";
        try {
            if (!InstallationState.pending || !InstallationState.allowed(request)) {
                throw new Exception("Setup is no longer available.");
            }
            InstallationDatabase.check(database);
            var native = InstallationDatabase.configuration(database);
            var values:Map<String, String> = [
                "APP_INSTALLED" => "true",
                "DB_DRIVER" => database.driver,
                "DB_PATH" => database.driver == "sqlite" ? native.path : "",
                "DB_HOST" => database.driver == "mysql" ? database.host : "",
                "DB_PORT" => Std.string(database.port),
                "DB_DATABASE" => database.database,
                "DB_USERNAME" => database.username,
                "DB_PASSWORD" => database.password,
                "SITE_NAME" => siteName,
                // The database keeps the administrator, with a hashed password; .env keeps none of it.
                "ADMIN_NAME" => "",
                "ADMIN_EMAIL" => "",
                "ADMIN_PASSWORD" => "",
                "CMS_SEED_DEMO" => inputs.get("sample_content") == "1" ? "true" : "false"
            ];
            phase = "configuration permissions";
            prepared = InstallationEnv.prepare(values);
            for (key => value in values) {
                previous.set(key, Environment.env(key, ""));
                Environment.set(key, value);
            }
            // Only this process sees the account details, while the schema setup creates the account.
            for (key => value in administrator) {
                Environment.set(key, value);
            }
            Config.set("database.connections", DatabaseConfig.definitions());
            Connection.create("default", native);
            phase = "database initialization";
            DatabaseProvider.migrate();
            forgetAdministrator(administrator);
            phase = "configuration commit";
            InstallationEnv.commit(prepared);
            prepared = null;
            InstallationState.complete();
            request.session.forget(InstallationDatabase.SESSION_KEY);
            request.session.forget(InstallationController.ADMINISTRATOR_KEY);
            phase = "runtime startup";
            #if jvm
            InstallationPlugins.retire();
            #end
            SiteRuntime.start();
            phase = "administrator sign-in";
            var admin = Admin.query.where("email", administrator.get("ADMIN_EMAIL"))
                .limit(1)
                .first();
            auth("admin").login(admin);
            request.session.put("auth_version", admin.password);
            InstallationState.locks.release("installation");
            if (View.redirectsValidation(request)) {
                return ResponseBuilder.asRedirect("/admin", 303)
                    .header("Cache-Control", "private, no-store");
            }
            return ResponseBuilder.asJson({installed: true, redirect: "/admin"})
                .header("Cache-Control", "private, no-store");
        } catch (failure:Dynamic) {
            forgetAdministrator(administrator);
            trace('Installation did not complete during ${phase}.');
            Connection.free();
            try {
                InstallationEnv.discard(prepared);
            } catch (_:Dynamic) {
                trace("The temporary installation configuration could not be removed.");
            }
            if (InstallationState.pending) {
                for (key => value in previous) {
                    Environment.set(key, value);
                }
            }
            InstallationState.locks.release("installation");
            if (!InstallationState.pending) {
                return failed(request,
                    "Installation was saved. Restart HaxePress and sign in to the administrator account.",
                    503, "review");
            }
            return failed(request,
                "Setup could not be completed. Check configuration-file permissions and use an empty, writable database before retrying.",
                422, "review");
        }
    }

    static function forgetAdministrator(administrator:Map<String, String>):Void {
        for (key in administrator.keys()) {
            Environment.set(key, "");
        }
    }
}
