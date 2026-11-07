package hx.press.config;

import hx.well.config.ConnectionTypedef;
import hx.well.config.IConfig;
import haxe.ds.StringMap;
import hx.well.facades.Environment;
import hx.well.facades.Storage;

using Std;

class DatabaseConfig implements IConfig {
    /** The SQLite file when DB_PATH is left out: the data folder, apart from the storage disk. **/
    public static inline var DEFAULT_SQLITE = "data/cms.sqlite";

    /** Where installations before the data folder kept that file. **/
    static inline var LEGACY_SQLITE = "storage/cms.sqlite";

    static var resolved:Null<{configured:String, path:String}> = null;

    public function new() {}

    /**
        The SQLite file: DB_PATH, or `data/cms.sqlite`. An installation that
        left DB_PATH out while its database was in `storage/` keeps using
        that file, so an upgrade never mistakes it for a new site.
    **/
    public static function sqlitePath():String {
        var configured = Environment.env("DB_PATH", "");
        var known = resolved;
        if (known != null && known.configured == configured) {
            return known.path;
        }
        var path = configured != "" ? configured : legacyDefault() ? LEGACY_SQLITE : DEFAULT_SQLITE;
        resolved = {configured: configured, path: path};
        return path;
    }

    static function legacyDefault():Bool {
        // Configuration loads before the storage disks, so this reads the project folder directly.
        var project = Storage.build({driver: "local", root: ".", read_only: true});
        return !project.fileExists(DEFAULT_SQLITE) && project.fileExists(LEGACY_SQLITE);
    }

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
                path: sqlitePath()
            }
        ];
    }
}
