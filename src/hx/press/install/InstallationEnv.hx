package hx.press.install;

import haxe.Exception;
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
        return "'" + escaped + "'";
    }

    public static function prepare(values:Map<String, String>):String {
        if (values.exists("APP_KEY")) {
            throw new Exception("Application keys are managed by HxWell's project bootstrap.");
        }
        var disk = Storage.disk("configuration");
        var source = disk.get(".env");
        var remaining = values.copy();
        var lines = [];
        for (line in source.split("\n")) {
            var match = ~/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=/;
            if (match.match(line) && values.exists(match.matched(1))) {
                var key = match.matched(1);
                if (remaining.exists(key)) {
                    lines.push(key + "=" + quoted(remaining.get(key)));
                    remaining.remove(key);
                }
            } else {
                lines.push(line);
            }
        }
        for (key => value in remaining) {
            lines.push(key + "=" + quoted(value));
        }
        var path = ".env.install-" + SecureToken.generate(16);
        disk.put(path, lines.join("\n") + "\n", "private");
        return path;
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
