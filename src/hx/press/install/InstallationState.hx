package hx.press.install;

import haxe.io.Path;
import hx.press.config.DatabaseConfig;
import hx.press.model.Admin;
import hx.well.database.Connection;
import hx.well.facades.Environment;
import hx.well.facades.Schema;
import hx.well.facades.Storage;
import hx.well.thread.MutexPool;
import hx.well.http.Request;
#if jvm
import java.net.InetAddress;
#end

class InstallationState {
    public static var pending(default, null) = false;
    public static var legacyFailure(default, null) = false;
    public static final locks = new MutexPool();

    public static function initialize():Void {
        var installed = Environment.env("APP_INSTALLED", "");
        if (installed == "true") {
            pending = false;
            return;
        }
        pending = true;
        if (installed == "false") {
            return;
        }
        var driver = Environment.env("DB_DRIVER", "sqlite");
        if (driver == "sqlite") {
            var filename = DatabaseConfig.sqlitePath();
            var parent = Path.directory(filename);
            var disk = Storage.build({
                driver: "local",
                root: parent == "" ? "." : parent,
                read_only: true
            });
            if (!disk.fileExists(Path.withoutDirectory(filename))) {
                return;
            }
        } else if (Environment.env("DB_DATABASE", "") == "") {
            return;
        }
        try {
            if (Schema.hasTable("admins") && Admin.query.select(["id"]).exists()) {
                pending = false;
            }
            Connection.free();
        } catch (_:Dynamic) {
            Connection.free();
            legacyFailure = true;
        }
    }

    static function normalized(address:String):Null<String> {
        if (address == null || address == "" || !~/^[0-9a-fA-F:.]+$/.match(address)) {
            return null;
        }
        if (address.indexOf(":") < 0) {
            if (!~/^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$/.match(address)) {
                return null;
            }
            for (part in address.split(".")) {
                if (Std.parseInt(part) > 255) {
                    return null;
                }
            }
        }
        #if jvm
        try {
            return InetAddress.getByName(address).getHostAddress();
        } catch (_:Dynamic) {
            return null;
        }
        #else
        var result = address.toLowerCase();
        return StringTools.startsWith(result, "::ffff:") ? result.substr(7) : result;
        #end
    }

    public static function trusted(address:String):Bool {
        var peer = normalized(address);
        if (peer == null || legacyFailure) {
            return false;
        }
        if (peer == "127.0.0.1") {
            return true;
        }
        var configured = Environment.env("INSTALL_TRUSTED_IPS", "");
        if (StringTools.trim(configured) == "") {
            return false;
        }
        for (entry in configured.split(",")) {
            var allowed = normalized(StringTools.trim(entry));
            if (allowed != null && allowed == peer) {
                return true;
            }
        }
        return false;
    }

    public static function allowed(request:Request):Bool {
        // Forwarded identity headers cannot establish first-install trust.
        if (request.header("Forwarded") != null || request.header("X-Forwarded-For") != null
            || request.header("X-Real-IP") != null) {
            return false;
        }
        return trusted(request.ip);
    }

    public static function blockedReason():String {
        if (legacyFailure) {
            return
                "The existing database could not be verified. Correct the server database settings before continuing.";
        }
        if (StringTools.trim(Environment.env("INSTALL_TRUSTED_IPS", "")) == "") {
            return
                "Configure INSTALL_TRUSTED_IPS on the server and restart HaxePress before starting setup.";
        }
        return
            "This connection is not allowed to start setup. Use an IP address listed in INSTALL_TRUSTED_IPS.";
    }

    public static function complete():Void {
        pending = false;
    }
}
