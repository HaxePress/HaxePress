package hx.press.handler.install;

import haxe.Exception;
import hx.press.CategoryData;
import hx.press.config.DatabaseConfig;
import hx.press.install.InstallationDatabase;
import hx.press.install.InstallationDatabase.SetupDatabase;
import hx.press.install.InstallationEnv;
import hx.press.install.InstallationState;
import hx.press.model.Admin;
import hx.press.provider.DatabaseProvider;
import hx.press.provider.SiteRuntime;
import hx.press.validation.ValidationResponder;
import hx.well.database.Connection;
import hx.well.facades.Config;
import hx.well.facades.Environment;
import hx.well.facades.Inertia;
import hx.well.handler.AbstractHandler;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.RequestStatic.request;
import hx.well.http.RequestStatic.auth;
import hx.well.http.ResponseBuilder;

class FinishInstallationHandler extends AbstractHandler implements ValidationResponder {
    public override function validate():Bool {
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
        return
            ResponseBuilder.asJson({error: "Check the site and administrator fields. Use a password between 12 and 72 bytes."},
            422);
    }

    public function execute(request:Request):AbstractResponse {
        var inputs = request.only("site_name", "admin_name", "admin_email", "admin_password",
            "confirm_password", "sample_content");
        var siteName = StringTools.trim(inputs.get("site_name"));
        var adminName = StringTools.trim(inputs.get("admin_name"));
        if (siteName.length < 2 || adminName.length < 2) {
            return validationFailed(request);
        }
        if (inputs.get("admin_password") != inputs.get("confirm_password")) {
            return ResponseBuilder.asJson({error: "The passwords do not match."}, 422);
        }
        var database:Null<SetupDatabase> = request.session.get(InstallationDatabase.SESSION_KEY);
        if (database == null
            || Date.now()
                .getTime() - database.checkedAt >= InstallationDatabase.VERIFICATION_LIFETIME) {
            return
                ResponseBuilder.asJson({error: "Verify the database connection again before continuing."},
                    409);
        }
        InstallationState.locks.acquire("installation");
        var prepared:Null<String> = null;
        var previous:Map<String, String> = [];
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
                "ADMIN_NAME" => adminName,
                "ADMIN_EMAIL" => CategoryData.key(inputs.get("admin_email")),
                "ADMIN_PASSWORD" => inputs.get("admin_password"),
                "CMS_SEED_DEMO" => inputs.get("sample_content") == "1" ? "true" : "false"
            ];
            phase = "configuration permissions";
            prepared = InstallationEnv.prepare(values);
            for (key => value in values) {
                previous.set(key, Environment.env(key, ""));
                Environment.set(key, value);
            }
            Config.set("database.connections", DatabaseConfig.definitions());
            Connection.create("default", native);
            phase = "database initialization";
            DatabaseProvider.migrate();
            phase = "configuration commit";
            InstallationEnv.commit(prepared);
            prepared = null;
            InstallationState.complete();
            request.session.forget(InstallationDatabase.SESSION_KEY);
            phase = "runtime startup";
            SiteRuntime.start();
            phase = "administrator sign-in";
            var admin = Admin.query.where("email", values.get("ADMIN_EMAIL")).limit(1).first();
            auth("admin").login(admin);
            request.session.put("auth_version", admin.password);
            Inertia.clearHistory();
            InstallationState.locks.release("installation");
            return ResponseBuilder.asJson({installed: true, redirect: "/admin"})
                .header("Cache-Control", "private, no-store");
        } catch (failure:Dynamic) {
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
                return
                    ResponseBuilder.asJson({error: "Installation was saved. Restart HaxePress and sign in to the administrator account."},
                    503)
                    .header("Cache-Control", "private, no-store");
            }
            return
                ResponseBuilder.asJson({error: "Setup could not be completed. Check configuration-file permissions and use an empty, writable database before retrying."},
                422)
                .header("Cache-Control", "private, no-store");
        }
    }
}
