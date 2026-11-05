package hx.press.config;

import hx.well.config.ConnectionTypedef;
import hx.well.config.IConfig;
import haxe.ds.StringMap;
import hx.well.facades.Environment;

using Std;

class DatabaseConfig implements IConfig {
    public function new() {}

    public var connections:StringMap<ConnectionTypedef> = definitions();

    public static function definitions():StringMap<ConnectionTypedef> {
        var driver = Environment.env("DB_DRIVER", "sqlite");
        if (driver == "mysql") {
            return [
                "default" => {
                    driver: "mysql",
                    host: Environment.env("DB_HOST", "127.0.0.1"),
                    port: Environment.env("DB_PORT", "3306").parseInt(),
                    database: Environment.env("DB_DATABASE", ""),
                    username: Environment.env("DB_USERNAME", ""),
                    password: Environment.env("DB_PASSWORD", "")
                }
            ];
        }
        return [
            "default" => {
                driver: "sqlite",
                path: Environment.env("DB_PATH", "storage/cms.sqlite")
            }
        ];
    }
}
