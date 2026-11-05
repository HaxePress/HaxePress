package hx.press.install;

import haxe.Exception;
import haxe.crypto.Md5;
import hx.well.database.Connection;
import hx.well.facades.Schema;
import hx.well.facades.Storage;
import hx.well.internal.SecureToken;

typedef SetupDatabase = {
    var driver:String;
    var file:String;
    var host:String;
    var port:Int;
    var database:String;
    var username:String;
    var password:String;
    var checkedAt:Float;
}

class InstallationDatabase {
    public static inline var SESSION_KEY = "haxepress.install.database";
    public static inline var VERIFICATION_LIFETIME = 10 * 60 * 1000;

    public static function configuration(database:SetupDatabase):Dynamic {
        if (database.driver == "sqlite") {
            var disk = Storage.disk("local");
            disk.makeDirectory("");
            return {path: disk.path(database.file)};
        }
        return {
            host: database.host,
            port: database.port,
            database: database.database,
            user: database.username,
            pass: database.password
        };
    }

    public static function check(database:SetupDatabase):Void {
        Connection.free();
        Connection.create("installation", configuration(database));
        var schema = Schema.connection("installation");
        try {
            var tables = schema.getTableListing();
            if (tables.length != 0) {
                throw new Exception("Choose an empty database. Existing data will not be overwritten.");
            }
            var table = "haxepress_setup_" + Md5.encode(SecureToken.generate(12)).substr(0, 12);
            // The schema probe verifies DDL access, not just a successful socket connection.
            schema.create(table, blueprint -> blueprint.id());
            schema.drop(table);
            Connection.free();
        } catch (error:Dynamic) {
            Connection.free();
            throw error;
        }
    }

    public static function summary(database:SetupDatabase):Dynamic {
        return {
            driver: database.driver,
            file: database.file,
            host: database.host,
            port: database.port,
            database: database.database,
            username: database.username
        };
    }
}
