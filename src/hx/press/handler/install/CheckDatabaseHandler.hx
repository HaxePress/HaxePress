package hx.press.handler.install;

import haxe.Exception;
import hx.press.AdminController;
import hx.press.install.InstallationDatabase;
import hx.press.install.InstallationDatabase.SetupDatabase;
import hx.press.install.InstallationState;
import hx.press.validation.Port;
import hx.press.validation.ValidationResponder;
import hx.press.view.View;
import hx.well.handler.AbstractHandler;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.RequestStatic.request;
import hx.well.http.ResponseBuilder;
import hx.well.validator.ValidatorRule;

class CheckDatabaseHandler extends AbstractHandler implements ValidationResponder {
    static inline final MYSQL_PORT = 3306;

    public override function validate():Bool {
        var rules:Map<String,
            Array<ValidatorRule>> = ["driver" => [Required, String, Regex("^(sqlite|mysql)\\z")]];
        if (request().input("driver", "") == "sqlite") {
            rules.set("file",
                [Required, String, Regex("^[A-Za-z0-9][A-Za-z0-9_.-]{0,74}\\.sqlite\\z")]);
        } else {
            rules.set("host", [Required, String, Max(253), Regex("^[A-Za-z0-9_.:-]+\\z")]);
            rules.set("port", [Required, String, Custom("cms.port")]);
            rules.set("database", [Required, String, Regex("^[A-Za-z0-9_][A-Za-z0-9_-]{0,63}\\z")]);
            rules.set("username", [Required, String, Min(1), Max(100), Custom("cms.line")]);
            rules.set("password", [String, Max(1000), Custom("cms.line")]);
        }
        return request().validate(rules);
    }

    public function validationFailed(request:Request):AbstractResponse {
        return failed(request,
            "Check the database fields and use a local .sqlite filename or valid MySQL connection details.");
    }

    /** JSON for scripts; the installer form returns to the database step with the error. **/
    static function failed(request:Request, message:String):AbstractResponse {
        var driver:Dynamic = request.input("driver", "");
        var selected = Std.string(driver) == "mysql" ? "mysql" : "sqlite";
        var redirect = AdminController.validationRedirect(request, "setup", message,
            '/admin/install?step=database&driver=${selected}');
        if (redirect != null) {
            return redirect.header("Cache-Control", "private, no-store");
        }
        return ResponseBuilder.asJson({error: message}, 422)
            .header("Cache-Control", "private, no-store");
    }

    public function execute(request:Request):AbstractResponse {
        var values = request.only("driver", "file", "host", "port", "database", "username",
            "password");
        // SQLite sends no port; MySQL's was checked by cms.port.
        var port = Port.parse(values.get("port")) ?? MYSQL_PORT;
        var file:String = values.get("file") ?? "cms.sqlite";
        if (file.indexOf("..") >= 0) {
            return validationFailed(request);
        }
        var database:SetupDatabase = {
            driver: values.get("driver"),
            file: file,
            host: values.get("host") ?? "127.0.0.1",
            port: port,
            database: values.get("database") ?? "",
            username: values.get("username") ?? "",
            password: values.get("password") ?? "",
            checkedAt: Date.now().getTime()
        };
        if (database.driver == "sqlite") {
            database.host = "";
            database.database = "";
            database.username = "";
            database.password = "";
        } else {
            database.file = "";
        }
        InstallationState.locks.acquire("installation");
        try {
            if (!InstallationState.pending) {
                throw new Exception("Setup has already completed.");
            }
            request.session.forget(InstallationDatabase.SESSION_KEY);
            InstallationDatabase.check(database);
            request.session.put(InstallationDatabase.SESSION_KEY, database);
            InstallationState.locks.release("installation");
            if (View.redirectsValidation(request)) {
                return ResponseBuilder.asRedirect("/admin/install", 303)
                    .header("Cache-Control", "private, no-store");
            }
            return ResponseBuilder.asJson({
                verified: true,
                database: InstallationDatabase.summary(database)
            }).header("Cache-Control", "private, no-store");
        } catch (_:Dynamic) {
            InstallationState.locks.release("installation");
            return failed(request,
                "The database could not be verified. Check its connection details, write permissions and that it is empty.");
        }
    }
}
