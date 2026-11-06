package hx.press.backup;

#if jvm
import haxe.Exception;
import haxe.io.Bytes;
import hx.press.AdminController;
import hx.press.CmsAccess;
import hx.press.CmsController;
import hx.press.access.Roles;
import hx.press.backup.BackupUploads.BackupUploadPurpose;
import hx.press.backup.SiteBackupArchive.BackupSelection;
import hx.press.backup.SiteBackupArchive.ExtractedBackup;
import hx.press.config.DatabaseConfig;
import hx.press.install.InstallationDatabase;
import hx.press.install.InstallationDatabase.SetupDatabase;
import hx.press.install.InstallationEnv;
import hx.press.install.InstallationState;
import hx.press.media.MediaLocks;
import hx.press.model.Admin;
import hx.press.packages.PackageManager;
import hx.press.packages.PackageBundles;
import hx.press.provider.SiteRuntime;
import hx.press.storage.TemporaryDownloadInput;
import hx.press.view.View;
import hx.well.database.Connection;
import hx.well.facades.Config;
import hx.well.facades.Environment;
import hx.well.facades.Storage;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.ResponseBuilder;
import hx.well.http.ResponseStatic.abort;
import hx.well.internal.SecureToken;
import hx.well.storage.StorageDisk;
import hx.well.thread.MutexPool;

class SiteBackup {
    public static inline var CAPABILITY = "backups";
    public static inline var PATH = "/admin/backups";
    static inline var EXPORTS = "site-backups";
    static inline var STAGING = "site-backup-staging";
    static inline var WORK = "backup-work";
    static inline var DOWNLOAD_SECONDS = 900;
    static final locks = new MutexPool();

    public static function supported():Bool {
        return ["sqlite", "mysql"].contains(Connection.driver());
    }

    public static function requireAccess():Admin {
        var admin = CmsAccess.current();
        if (admin == null || !Roles.can(admin.role, CAPABILITY)) {
            abort(403);
        }
        return admin;
    }

    public static function page(request:Request):AbstractResponse {
        if (!CmsAccess.can(CAPABILITY)) {
            return CmsController.forbidden(request);
        }
        var available = supported();
        var schedules = available ? BackupViews.schedules(BackupSchedules.list()) : [];
        var scheduleForm = available ? BackupViews.scheduleForm(request, schedules) : null;
        var props = {
            supported: available,
            uploadLimit: BackupFormat.maxBytes(),
            schedules: schedules,
            backupForm: BackupViews.backupForm(request),
            scheduleForm: scheduleForm,
            savedFiles: available ? BackupViews.savedFiles(request, schedules) : null,
            editing: scheduleForm != null
        };
        return View.render("Admin/Backups", props).header("Cache-Control", "private, no-store");
    }

    public static function export(request:Request):AbstractResponse {
        var admin = requireAccess();
        if (!supported()) {
            return error("Site backups require SQLite or MySQL.");
        }
        var sections = {
            content: selected(request, "content"),
            themes: selected(request, "themes"),
            plugins: selected(request, "plugins")
        };
        if (!sections.content && !sections.themes && !sections.plugins) {
            return exportFailed(request, "Choose at least one backup section.");
        }
        var encrypted = selected(request, "encrypted");
        locks.acquire(EXPORTS);
        try {
            var verified = prepare(admin.id, sections, encrypted);
            locks.release(EXPORTS);
            if (View.redirectsValidation(request)) {
                // The backups page offers the verified download once.
                View.flash("backup", verified);
                View.flash("old", AdminController.submittedInput(request));
                return ResponseBuilder.asRedirect(PATH, 303);
            }
            return ResponseBuilder.asJson(verified).header("Cache-Control", "private, no-store");
        } catch (failure:Dynamic) {
            locks.release(EXPORTS);
            return exportFailed(request, Std.string(failure));
        }
    }

    /** A backup section chosen as a JSON `true` or a checked form box (`1`). **/
    static function selected(request:Request, key:String):Bool {
        var value:Dynamic = request.input(key, false);
        if (Std.isOfType(value, Bool)) {
            return value;
        }
        return Std.isOfType(value, String) && value == "1";
    }

    static function exportFailed(request:Request, message:String):AbstractResponse {
        var redirect = AdminController.validationRedirect(request, "backup", message, PATH);
        return redirect ?? error(message);
    }

    static function prepare(adminId:Int, sections:BackupSelection, encrypted:Bool):Dynamic {
        var token = SecureToken.generate(32);
        var directory = '${EXPORTS}/${adminId}';
        var archive = '${directory}/${token}.${BackupFormat.EXTENSION}';
        var pending = '${STAGING}/${token}.${BackupFormat.EXTENSION}';
        var exports = Storage.disk("exports");
        try {
            var md5 = createArchive(exports, pending, sections, encrypted);
            exports.move(pending, archive);
            for (path in exports.files(directory)) {
                if (path != archive) {
                    exports.delete(path);
                }
            }
            return {download: '${PATH}/downloads/${token}', md5: md5};
        } catch (failure:Dynamic) {
            exports.delete(pending);
            exports.delete(archive);
            throw failure;
        }
    }

    public static function createArchive(target:StorageDisk, destination:String,
            sections:BackupSelection, encrypted:Bool):String {
        if (!supported()) {
            throw new Exception("Site backups require SQLite or MySQL.");
        }
        var token = SecureToken.generate(32);
        var workspace = '${WORK}/${token}';
        var local = Storage.disk("local");
        var snapshot = scoped('${workspace}/source');
        var zip = "archive.zip";
        var appKey = Environment.env("APP_KEY", "");
        try {
            PackageManager.writes.acquire("packages");
            try {
                MediaLocks.run(() -> {
                    var manifest = SiteBackupArchive.manifest(sections, appKey);
                    var files = [manifest].concat(SiteBackupDatabase.exportData(snapshot, local,
                        sections));
                    SiteBackupArchive.write(snapshot, zip, files);
                    return true;
                });
                PackageManager.writes.release("packages");
            } catch (failure:Dynamic) {
                PackageManager.writes.release("packages");
                throw failure;
            }
            BackupFormat.seal(snapshot, zip, target, destination, encrypted, appKey);
            var checksum = rehearse(target, destination, scoped('${workspace}/review'));
            local.deleteDirectory(workspace);
            return checksum;
        } catch (failure:Dynamic) {
            target.delete(destination);
            local.deleteDirectory(workspace);
            throw failure;
        }
    }

    public static function download(request:Request):AbstractResponse {
        var admin = requireAccess();
        var token = request.route("token");
        if (token == null || !~/^[A-Za-z0-9_-]{32}$/.match(token)) {
            abort(404);
        }
        var disk = Storage.disk("exports");
        var path = '${EXPORTS}/${admin.id}/${token}.${BackupFormat.EXTENSION}';
        if (!disk.fileExists(path) || expired(disk, path)) {
            abort(404);
        }
        var day = DateTools.format(Date.now(), "%Y-%m-%d");
        var response = disk.download(path, 'haxepress-backup-${day}.${BackupFormat.EXTENSION}', [
            "Content-Type" => "application/octet-stream",
            "Cache-Control" => "private, no-store"
        ]);
        response.input = new TemporaryDownloadInput(response.input, () -> disk.delete(path));
        return response;
    }

    public static function cleanup():Void {
        BackupUploads.expire();
        var disk = Storage.disk("exports");
        for (path in disk.allFiles(EXPORTS).concat(disk.files(STAGING))) {
            if (expired(disk, path)) {
                disk.delete(path);
            }
        }
    }

    static function expired(disk:StorageDisk, path:String):Bool {
        return Date.now().getTime() / 1000 - disk.lastModified(path) >= DOWNLOAD_SECONDS;
    }

    public static function verify(request:Request):AbstractResponse {
        requireAccess();
        var token = SecureToken.generate(32);
        var workspace = '${WORK}/${token}';
        var archive = '${workspace}/upload.hxpress';
        var local = Storage.disk("local");
        locks.acquire(EXPORTS);
        try {
            BackupUploads.assemble(request, BackupUploadPurpose.Verify, local, archive);
            var md5 = rehearse(local, archive, scoped('${workspace}/review'));
            local.deleteDirectory(workspace);
            locks.release(EXPORTS);
            return ResponseBuilder.asJson({verified: true, md5: md5})
                .header("Cache-Control", "private, no-store");
        } catch (failure:Dynamic) {
            try {
                local.deleteDirectory(workspace);
            } catch (_:Dynamic) {
                trace("Could not clean up the backup workspace.");
            }
            locks.release(EXPORTS);
            return error(Std.string(failure));
        }
    }

    static function rehearse(disk:StorageDisk, archive:String, review:StorageDisk):String {
        var backup = extract(disk, archive, review, false);
        var database = SiteBackupDatabase.RESTORED;
        review.put(database, Bytes.alloc(0), "private");
        SiteBackupDatabase.replay(review, backup, {path: review.path(database)}, true, false);
        return backup.md5;
    }

    static function extract(disk:StorageDisk, archive:String, stage:StorageDisk,
            skipDamaged:Bool):ExtractedBackup {
        var appKey = Environment.env("APP_KEY", "");
        var zip = "archive.zip";
        var encrypted = BackupFormat.open(disk, archive, stage, zip, appKey);
        var backup = SiteBackupArchive.extract(stage, zip, stage, skipDamaged);
        stage.delete(zip);
        if (encrypted && backup.manifest.appKey != appKey) {
            throw new Exception("The encrypted backup belongs to a different APP_KEY.");
        }
        return backup;
    }

    public static function restore(request:Request):AbstractResponse {
        var token = SecureToken.generate(32);
        var workspace = '${WORK}/${token}';
        var local = Storage.disk("local");
        InstallationState.locks.acquire("installation");
        if (!InstallationState.pending) {
            InstallationState.locks.release("installation");
            abort(404);
        }
        var moved:Array<String> = [];
        var prepared:Null<String> = null;
        var ownedDatabase:Null<String> = null;
        var committed = false;
        try {
            var selected:Null<SetupDatabase> = null;
            if (request.query("use_verified_database") == "1") {
                selected = request.session.get(InstallationDatabase.SESSION_KEY);
                if (selected == null
                    || Date.now()
                        .getTime() - selected.checkedAt >= InstallationDatabase.VERIFICATION_LIFETIME) {
                    throw new Exception("Verify the target database again before restoring.");
                }
            }
            var archive = '${workspace}/upload.hxpress';
            BackupUploads.assemble(request, BackupUploadPurpose.Restore, local, archive);
            var stage = scoped('${workspace}/restore');
            var skipDamaged = request.query("skip_damaged_content") == "1";
            var backup = extract(local, archive, stage, skipDamaged);
            var generated = selected == null;
            var database:SetupDatabase = generated ? {
                driver: "sqlite",
                file: 'restored-${token}.sqlite',
                host: "",
                port: 3306,
                database: "",
                username: "",
                password: "",
                checkedAt: 0
            } : selected;
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
            prepared = InstallationEnv.prepareRestore(values, backup.manifest.appKey);
            for (path in backup.files) {
                if (local.exists(path)) {
                    throw new Exception("Restore requires an empty site storage directory.");
                }
            }
            var publish = () -> {
                for (path in backup.files) {
                    local.move('${workspace}/restore/${path}', path);
                    moved.push(path);
                }
                InstallationEnv.commit(prepared);
                committed = true;
            };
            if (generated) {
                local.put(database.file, Bytes.alloc(0), "private");
                ownedDatabase = database.file;
            }
            var skipped = SiteBackupDatabase.replay(stage, backup, native, false, skipDamaged,
                publish);
            for (key => value in values) {
                Environment.set(key, value);
            }
            Environment.set("APP_KEY", backup.manifest.appKey);
            Config.set("database.connections", DatabaseConfig.definitions());
            Connection.free();
            Connection.create("default", native);
            PackageBundles.ensure();
            InstallationState.complete();
            request.session.forget(InstallationDatabase.SESSION_KEY);
            SiteRuntime.start();
            local.deleteDirectory(workspace);
            InstallationState.locks.release("installation");
            return ResponseBuilder.asJson({
                restored: true,
                redirect: "/admin/login",
                skippedContent: skipped
            }).header("Cache-Control", "private, no-store");
        } catch (failure:Dynamic) {
            try {
                if (!committed) {
                    InstallationEnv.discard(prepared);
                    for (path in moved) {
                        local.delete(path);
                    }
                    if (ownedDatabase != null) {
                        local.delete(ownedDatabase);
                    }
                }
                local.deleteDirectory(workspace);
            } catch (_:Dynamic) {
                trace("Could not clean up the backup workspace.");
            }
            InstallationState.locks.release("installation");
            return committed ? error("The backup was restored. Restart HaxePress and sign in.",
                503) : error(Std.string(failure));
        }
    }

    static function scoped(prefix:String):StorageDisk {
        return Storage.build({
            driver: "scoped",
            disk: "local",
            prefix: prefix,
            throw_errors: true
        });
    }

    static function error(message:String, status:Int = 422):AbstractResponse {
        return ResponseBuilder.asJson({error: message}, status)
            .header("Cache-Control", "private, no-store");
    }
}
#end
