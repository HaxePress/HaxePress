package hx.press.handler.install;

import haxe.Exception;
import hx.press.install.InstallationDatabase;
import hx.press.install.InstallationDatabase.SetupDatabase;
import hx.press.install.InstallationState;
import hx.press.validation.ValidationResponder;
import hx.well.handler.AbstractHandler;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.RequestStatic.request;
import hx.well.http.ResponseBuilder;
import hx.well.validator.ValidatorRule;

class CheckDatabaseHandler extends AbstractHandler implements ValidationResponder {
    public override function validate():Bool {
        var rules:Map<String,
            Array<ValidatorRule>> = ["driver" => [Required, String, Regex("^(sqlite|mysql)$")]];
        if (request().input("driver", "") == "sqlite") {
            rules.set("file",
                [Required, String, Regex("^[A-Za-z0-9][A-Za-z0-9_.-]{0,74}\\.sqlite$")]);
        } else {
            rules.set("host", [Required, String, Max(253), Regex("^[A-Za-z0-9_.:-]+$")]);
            rules.set("port", [Required, String, Regex("^[0-9]{1,5}$")]);
            rules.set("database", [Required, String, Regex("^[A-Za-z0-9_][A-Za-z0-9_-]{0,63}$")]);
            rules.set("username", [Required, String, Max(100), Regex("^[^\\x00-\\x1f\\x7f]+$")]);
            rules.set("password", [String, Max(1000), Regex("^[^\\x00-\\x1f\\x7f]*$")]);
        }
        return request().validate(rules);
    }

    public function validationFailed(request:Request):AbstractResponse {
        return
            ResponseBuilder.asJson({error: "Check the database fields and use a local .sqlite filename or valid MySQL connection details."},
            422);
    }

    public function execute(request:Request):AbstractResponse {
        var values = request.only("driver", "file", "host", "port", "database", "username",
            "password");
        var port = Std.parseInt(values.get("port") ?? "3306");
        if (port == null || port < 1 || port > 65535) {
            return validationFailed(request);
        }
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
            return ResponseBuilder.asJson({
                verified: true,
                database: InstallationDatabase.summary(database)
            }).header("Cache-Control", "private, no-store");
        } catch (_:Dynamic) {
            InstallationState.locks.release("installation");
            return
                ResponseBuilder.asJson({error: "The database could not be verified. Check its connection details, write permissions and that it is empty."},
                422)
                .header("Cache-Control", "private, no-store");
        }
    }
}
