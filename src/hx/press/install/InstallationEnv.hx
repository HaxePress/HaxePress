package hx.press.install;

import haxe.Exception;
import hx.well.facades.Environment;
import hx.well.facades.Storage;
import hx.well.internal.SecureToken;

/** Preserve unrelated settings and use literal, private dotenv values for credentials. */
class InstallationEnv {
    static function quoted(value:String):String {
        if (~/[\x00-\x1f\x7f]/.match(value)) {
            throw new Exception("Configuration values cannot contain control characters.");
        }
        var escaped = StringTools.replace(value, "\\", "\\\\");
        escaped = StringTools.replace(escaped, "'", "\\'");
        return '\'${escaped}\'';
    }

    public static function prepare(values:Map<String, String>):String {
        if (values.exists("APP_KEY")) {
            throw new Exception("Application keys are managed by HxWell's project bootstrap.");
        }
        return prepareValues(values);
    }

    public static function prepareRestore(values:Map<String, String>, appKey:String):String {
        var restored = values.copy();
        restored.set("APP_KEY", appKey);
        return prepareValues(restored);
    }

    static function prepareValues(values:Map<String, String>):String {
        var disk = Storage.disk("configuration");
        var source = disk.get(".env");
        var remaining = values.copy();
        var lines = [];
        for (line in source.split("\n")) {
            var match = ~/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=/;
            if (match.match(line) && values.exists(match.matched(1))) {
                var key = match.matched(1);
                if (remaining.exists(key)) {
                    lines.push('${key}=${quoted(remaining.get(key))}');
                    remaining.remove(key);
                }
            } else {
                lines.push(line);
            }
        }
        for (key => value in remaining) {
            lines.push('${key}=${quoted(value)}');
        }
        var path = '.env.install-${SecureToken.generate(16)}';
        disk.put(path, '${lines.join("\n")}\n', "private");
        return path;
    }

    /** The settings that create the first administrator when no account exists yet. **/
    public static final ADMINISTRATOR = ["ADMIN_NAME", "ADMIN_EMAIL", "ADMIN_PASSWORD"];

    /**
        Clears the first administrator's name, e-mail and password from .env
        once the account exists. The database holds the account and the
        only, hashed copy of its password; earlier installers also left them
        in .env. Nothing is read when the loaded settings hold none of them.
    **/
    public static function forgetAdministrator():Void {
        var present = ADMINISTRATOR.filter(key -> Environment.env(key, "") != "");
        if (present.length == 0) {
            return;
        }
        for (key in ADMINISTRATOR) {
            Environment.set(key, "");
        }
        var disk = Storage.disk("configuration");
        if (!disk.fileExists(".env")) {
            return;
        }
        var setting = ~/^\s*(ADMIN_NAME|ADMIN_EMAIL|ADMIN_PASSWORD)\s*=\s*(.*?)\s*$/;
        var changed = false;
        var lines = [];
        for (line in disk.get(".env").split("\n")) {
            if (setting.match(line) && !["", "''", '""'].contains(setting.matched(2))) {
                lines.push('${setting.matched(1)}=${quoted("")}');
                changed = true;
            } else {
                lines.push(line);
            }
        }
        if (!changed) {
            return;
        }
        var path = '.env.install-${SecureToken.generate(16)}';
        disk.put(path, lines.join("\n"), "private");
        disk.move(path, ".env");
    }

    public static function commit(path:String):Void {
        var disk = Storage.disk("configuration");
        disk.move(path, ".env");
    }

    public static function discard(path:String):Void {
        if (path != null) {
            Storage.disk("configuration").delete(path);
        }
    }
}
