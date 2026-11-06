package hx.press.install;

#if jvm
import haxe.Exception;
import haxe.io.Bytes;
import hx.press.config.DatabaseConfig;
import hx.press.install.InstallationDatabase.SetupDatabase;
import hx.press.packages.PackageBundles;
import hx.press.provider.SiteRuntime;
import hx.well.database.Connection;
import hx.well.facades.Config;
import hx.well.facades.Environment;
import hx.well.facades.Storage;
import hx.well.http.Request;
import hx.well.http.ResponseStatic.abort;
import hx.well.internal.SecureToken;
import hx.well.route.Route;

/** Where installing from a source writes. **/
typedef InstallationTarget = {
    /** `sqlite` or `mysql`. **/
    var driver:String;

    /** The verified database's file or name; empty for a new SQLite file. **/
    var label:String;

    var verified:Bool;
}

/** The site's configuration was installed, but HaxePress could not start with it. **/
class InstallationIncomplete extends Exception {}

/**
    The installation API for bundled plugins with the `installation` hook
    (see `InstallationPlugins`): routes on the installation page and
    installing a site from a source, such as a backup, instead of the
    setup form.
**/
class Installation {
    /** Whether HaxePress is still waiting to be installed. **/
    public static function pending():Bool {
        return InstallationState.pending;
    }

    /** Registers routes under `/admin/install`, behind the installer's access, session and CSRF checks. **/
    public static function routes(callback:Void->Void):Void {
        Route.path("/admin/install").middleware(InstallationRoutes.middlewares()).group(callback);
    }

    /** The database a source installs into: the one this visitor verified, or a new SQLite file. **/
    public static function target(request:Request, useVerified:Bool):InstallationTarget {
        if (!useVerified) {
            return {driver: "sqlite", label: "", verified: false};
        }
        var database = verified(request);
        return {
            driver: database.driver,
            label: database.driver == "sqlite" ? database.file : database.database,
            verified: true
        };
    }

    /**
        Installs HaxePress from a source. Installation is locked while it
        runs, and an installed site answers 404. `populate` receives the
        empty target database as a connection configuration for
        `Connection.withConfiguration`, fills it and calls `commit` once the
        site's data and files are complete: the configuration, with the
        source's `APP_KEY`, is written then. HaxePress then starts as an
        installed site and the result of `populate` is returned.

        A failure before `commit` leaves nothing behind; a database file
        created for the source is removed. After `commit`, a failure throws
        `InstallationIncomplete`: HaxePress must restart with the installed
        configuration.
    **/
    public static function install<T>(request:Request, useVerified:Bool, appKey:String,
            populate:(database:Dynamic, commit:Void->Void) -> T):T {
        InstallationState.locks.acquire("installation");
        if (!InstallationState.pending) {
            InstallationState.locks.release("installation");
            abort(404);
        }
        var local = Storage.disk("local");
        var prepared:Null<String> = null;
        var ownedDatabase:Null<String> = null;
        var committed = false;
        try {
            var generated = !useVerified;
            var database:SetupDatabase = generated ? {
                driver: "sqlite",
                file: 'restored-${SecureToken.generate(32)}.sqlite',
                host: "",
                port: 3306,
                database: "",
                username: "",
                password: "",
                checkedAt: 0
            } : verified(request);
            var native = InstallationDatabase.configuration(database);
            var values:Map<String, String> = [
                "APP_INSTALLED" => "true",
                "DB_DRIVER" => database.driver,
                "DB_PATH" => database.driver == "sqlite" ? native.path : "",
                "DB_HOST" => database.host,
                "DB_PORT" => Std.string(database.port),
                "DB_DATABASE" => database.database,
                "DB_USERNAME" => database.username,
                "DB_PASSWORD" => database.password,
                "ADMIN_NAME" => "",
                "ADMIN_EMAIL" => "",
                "ADMIN_PASSWORD" => "",
                "CMS_SEED_DEMO" => "false"
            ];
            prepared = InstallationEnv.prepareRestore(values, appKey);
            if (generated) {
                local.put(database.file, Bytes.alloc(0), "private");
                ownedDatabase = database.file;
            }
            var commit = () -> {
                InstallationEnv.commit(prepared);
                committed = true;
            };
            var result = populate(native, commit);
            if (!committed) {
                throw new Exception("The installation source did not complete the site.");
            }
            for (key => value in values) {
                Environment.set(key, value);
            }
            Environment.set("APP_KEY", appKey);
            Config.set("database.connections", DatabaseConfig.definitions());
            Connection.free();
            Connection.create("default", native);
            PackageBundles.ensure();
            InstallationState.complete();
            request.session.forget(InstallationDatabase.SESSION_KEY);
            InstallationPlugins.retire();
            SiteRuntime.start();
            InstallationState.locks.release("installation");
            return result;
        } catch (failure:Dynamic) {
            if (!committed) {
                try {
                    InstallationEnv.discard(prepared);
                    if (ownedDatabase != null) {
                        local.delete(ownedDatabase);
                    }
                } catch (_:Dynamic) {
                    trace("Could not remove the prepared installation.");
                }
            }
            InstallationState.locks.release("installation");
            if (committed) {
                throw new InstallationIncomplete(Std.string(failure));
            }
            throw failure;
        }
    }

    static function verified(request:Request):SetupDatabase {
        var selected:Null<SetupDatabase> = request.session.get(InstallationDatabase.SESSION_KEY);
        if (selected == null
            || Date.now()
                .getTime() - selected.checkedAt >= InstallationDatabase.VERIFICATION_LIFETIME) {
            throw new Exception("Verify the target database again before restoring.");
        }
        return selected;
    }
}
#end
