package hx.press.config;

import hx.press.validation.Port;
import hx.well.config.ConnectionTypedef;
import hx.well.config.IConfig;
import haxe.ds.StringMap;
import hx.well.facades.Environment;

class DatabaseConfig implements IConfig {
    /** The SQLite file when DB_PATH is left out, in the private database folder. **/
    public static inline var DEFAULT_SQLITE = "private/database/cms.sqlite";

    public function new() {}

    /** The SQLite file: DB_PATH, or `private/database/cms.sqlite`. **/
    public static function sqlitePath():String {
        var configured = Environment.env("DB_PATH", "");
        return configured != "" ? configured : DEFAULT_SQLITE;
    }

    public var connections:StringMap<ConnectionTypedef> = definitions();

    public static function definitions():StringMap<ConnectionTypedef> {
        var driver = Environment.env("DB_DRIVER", "sqlite");
        if (driver == "mysql") {
            return [
                "default" => {
                    driver: "mysql",
                    host: Environment.env("DB_HOST", "127.0.0.1"),
                    port: Port.setting("DB_PORT", Environment.env("DB_PORT", "3306")),
                    database: Environment.env("DB_DATABASE", ""),
                    username: Environment.env("DB_USERNAME", ""),
                    password: Environment.env("DB_PASSWORD", "")
                }
            ];
        }
        return [
            "default" => {
                driver: "sqlite",
                path: sqlitePath()
            }
        ];
    }
}
