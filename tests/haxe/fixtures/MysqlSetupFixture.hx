package fixtures;

import haxe.Exception;
import java.NativeArray;
import hx.well.config.ConfigData;
import hx.well.database.Connection;
import hx.well.facades.Environment;
import hx.well.facades.Schema;

@:keep
@:nativeGen
class MysqlSetupFixture {
    public static function main(arguments:NativeArray<String>):Void {
        Environment.load(".env");
        if (Environment.env("APP_NAME") != "haxepress_test") {
            throw new Exception("MySQL setup fixture requires an isolated test environment.");
        }
        ConfigData.init();
        Connection.create("mysql_fixture", {
            host: "127.0.0.1",
            port: Std.parseInt(arguments[0]),
            user: "root",
            pass: "",
            database: ""
        });
        var schema = Schema.connection("mysql_fixture");
        if (arguments.length > 2 && arguments[2] == "drop") {
            schema.dropDatabaseIfExists(arguments[1]);
        } else {
            schema.createDatabase(arguments[1]);
        }
        Connection.free();
    }
}
