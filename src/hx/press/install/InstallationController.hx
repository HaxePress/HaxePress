package hx.press.install;

import haxe.ds.StringMap;
import hx.press.i18n.I18n;
import hx.press.install.InstallationDatabase.SetupDatabase;
import hx.press.view.View;
import hx.well.http.Request;
import hx.well.http.Response;
import hx.well.middleware.CsrfMiddleware;
#if jvm
import hx.press.backup.BackupFormat;
#end

/** The administrator entered on the second step, kept in the session for the review. */
typedef SetupAdministrator = {
    var site_name:String;
    var admin_name:String;
    var admin_email:String;
    var admin_password:String;
}

/**
    The installer, a wizard of server-rendered steps: each step posts its
    form and the next page renders from the session (`?step=database`,
    `administrator` or `review`). There is no database yet, so the page
    reads no site settings and is shown in English, as before.
**/
class InstallationController {
    public static inline var ADMINISTRATOR_KEY = "haxepress.install.administrator";
    static final drivers = ["sqlite", "mysql"];

    public static function locked(request:Request):Response {
        var install = view(0, "sqlite", null, null, null, 0);
        install.blocked = true;
        install.message = InstallationState.blockedReason();
        var props = {
            setup: {
                blocked: true,
                message: install.message,
                database: null
            },
            install: install
        };
        shareLocale();
        return View.render("Admin/Install", props)
            .status(403)
            .header("Cache-Control", "private, no-store");
    }

    public static function page(request:Request):Response {
        var database = verifiedDatabase(request);
        var administrator:Null<SetupAdministrator> = request.session.get(ADMINISTRATOR_KEY);
        var requested = request.query("step", "");
        var step = 0;
        if (database != null && requested != "database") {
            step = requested == "review" && administrator != null ? 2 : 1;
        }
        var submitted = submittedInput(request);
        var selected = request.query("driver", submitted == null ? "" : text(submitted, "driver"));
        var driver = drivers.contains(selected) ? selected : database == null ? "sqlite" : database.driver;
        var restoreLimit = #if jvm BackupFormat.maxBytes() #else 0 #end;
        var install = view(step, driver, database, administrator, submitted, restoreLimit);
        var props = {
            setup: {
                blocked: false,
                message: "",
                database: database == null ? null : InstallationDatabase.summary(database),
                restoreLimit: restoreLimit
            },
            csrfToken: request.session.get(CsrfMiddleware.TOKEN_KEY),
            install: install
        };
        shareLocale();
        return View.render("Admin/Install", props).header("Cache-Control", "private, no-store");
    }

    /** The database verified within its lifetime, as the next steps require. **/
    public static function verifiedDatabase(request:Request):Null<SetupDatabase> {
        var database:Null<SetupDatabase> = request.session.get(InstallationDatabase.SESSION_KEY);
        if (database == null
            || Date.now()
                .getTime() - database.checkedAt >= InstallationDatabase.VERIFICATION_LIFETIME) {
            return null;
        }
        return database;
    }

    /** The installer is English and has no site settings yet, so the layout gets a fixed locale. **/
    static function shareLocale():Void {
        View.share("i18n", {locale: I18n.FALLBACK, direction: "ltr", locales: I18n.locales});
    }

    static function submittedInput(request:Request):Null<Map<String, Dynamic>> {
        var flashed:Dynamic = View.flashed(request, "old");
        return Std.isOfType(flashed, StringMap) ? cast flashed : null;
    }

    static function text(values:Null<Map<String, Dynamic>>, key:String,
            fallback:String = ""):String {
        var value:Dynamic = values == null ? null : values.get(key);
        return Std.isOfType(value, String) ? value : fallback;
    }

    static function view(step:Int, driver:String, database:Null<SetupDatabase>,
            administrator:Null<SetupAdministrator>, submitted:Null<Map<String, Dynamic>>,
            restoreLimit:Int):Dynamic {
        var sqlite = database == null || database.driver == "sqlite";
        var verifiedLabel = database == null ? "" : sqlite ? database.file : database.database;
        var reviewDatabase = database == null ? "" : sqlite ? 'SQLite · ${database.file}' : 'MySQL · ${database.host}:${database.port} / ${database.database}';
        var restoreTarget = step == 1
            && database != null ? 'Restore into ${verifiedLabel}.' : "Restore into a new SQLite database.";
        var port = database == null
            || database.driver != "mysql" ? "3306" : Std.string(database.port);
        return {
            blocked: false,
            message: "",
            step: step,
            driver: driver,
            file: text(submitted,
                "file", database == null || database.file == "" ? "cms.sqlite" : database.file),
            host: text(submitted,
                "host", database == null || database.host == "" ? "127.0.0.1" : database.host),
            port: text(submitted, "port", port),
            database: text(submitted, "database", database == null ? "" : database.database),
            username: text(submitted, "username", database == null ? "" : database.username),
            verifiedLabel: verifiedLabel,
            reviewDatabase: reviewDatabase,
            siteName: text(submitted, "site_name",
                administrator == null ? "HaxePress" : administrator.site_name),
            adminName: text(submitted, "admin_name",
                administrator == null ? "" : administrator.admin_name),
            adminEmail: text(submitted, "admin_email",
                administrator == null ? "" : administrator.admin_email),
            showRestore: restoreLimit > 0 && ((step == 0 && driver == "sqlite") || step == 1),
            restoreTarget: restoreTarget,
            useVerifiedDatabase: step == 1 && database != null,
            restoreLimit: restoreLimit
        };
    }
}
