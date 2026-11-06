package extensions.backup;

#if jvm
import haxe.Exception;
import haxe.io.Bytes;
import hx.press.CmsAccess;
import hx.press.access.Roles;
import extensions.backup.BackupUploads.BackupUploadPurpose;
import extensions.backup.SiteBackupArchive.BackupSelection;
import extensions.backup.SiteBackupArchive.ExtractedBackup;
import hx.press.install.Installation;
import hx.press.install.Installation.InstallationIncomplete;
import hx.press.model.Admin;
import hx.press.storage.TemporaryDownloadInput;
import hx.press.view.Flash;
import hx.press.view.Pages;
import hx.well.database.Connection;
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
            var denied = {message: "Your account does not have access to this area."};
            return Pages.render("Admin/Forbidden", denied).status(403);
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
        return Pages.view("Backups", props).header("Cache-Control", "private, no-store");
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
            if (Pages.redirectsValidation(request)) {
                // The backups page offers the verified download once.
                Flash.put("backup", verified);
                Flash.put("old", submittedInput(request));
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
        var redirect = Pages.validationRedirect(request, "backup", message, PATH);
        return redirect ?? error(message);
    }

    /** The submitted form values without the CSRF token, shown again with the result. **/
    static function submittedInput(request:Request):Map<String, String> {
        var values:Map<String, String> = [];
        for (key => value in request.all()) {
            if (key != "_token" && Std.isOfType(value, String) && (value : String).length <= 200) {
                values.set(key, value);
            }
        }
        return values;
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
            // The host holds the package and media locks this plugin declares while it runs.
            var manifest = SiteBackupArchive.manifest(sections, appKey);
            var files = [manifest].concat(SiteBackupDatabase.exportData(snapshot, local, sections));
            SiteBackupArchive.write(snapshot, zip, files);
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

    /**
        Installs a new site from an uploaded backup, from the installation
        page: the backup's data, files and APP_KEY become the site.
    **/
    public static function restore(request:Request):AbstractResponse {
        if (!Installation.pending()) {
            abort(404);
        }
        var token = SecureToken.generate(32);
        var workspace = '${WORK}/${token}';
        var local = Storage.disk("local");
        var moved:Array<String> = [];
        var published = false;
        try {
            var useVerified = request.query("use_verified_database") == "1";
            // Checks the verified database before reading the upload.
            Installation.target(request, useVerified);
            var archive = '${workspace}/upload.hxpress';
            BackupUploads.assemble(request, BackupUploadPurpose.Restore, local, archive);
            var stage = scoped('${workspace}/restore');
            var skipDamaged = request.query("skip_damaged_content") == "1";
            var backup = extract(local, archive, stage, skipDamaged);
            for (path in backup.files) {
                if (local.exists(SiteBackupDatabase.storagePath(path))) {
                    throw new Exception("Restore requires an empty site storage directory.");
                }
            }
            var skipped = Installation.install(request, useVerified, backup.manifest.appKey,
                (database,
                        commit) -> SiteBackupDatabase.replay(stage, backup, database, false,
                        skipDamaged, () -> {
                            for (path in backup.files) {
                                var target = SiteBackupDatabase.storagePath(path);
                                local.move('${workspace}/restore/${path}', target);
                                moved.push(target);
                            }
                            commit();
                            published = true;
                        }));
            local.deleteDirectory(workspace);
            return ResponseBuilder.asJson({
                restored: true,
                redirect: "/admin/login",
                skippedContent: skipped
            }).header("Cache-Control", "private, no-store");
        } catch (incomplete:InstallationIncomplete) {
            cleanWorkspace(local, workspace);
            return error("The backup was restored. Restart HaxePress and sign in.", 503);
        } catch (failure:Dynamic) {
            if (!published) {
                for (path in moved) {
                    try {
                        local.delete(path);
                    } catch (_:Dynamic) {}
                }
            }
            cleanWorkspace(local, workspace);
            return published ? error("The backup was restored. Restart HaxePress and sign in.",
                503) : error(Std.string(failure));
        }
    }

    static function cleanWorkspace(local:StorageDisk, workspace:String):Void {
        try {
            local.deleteDirectory(workspace);
        } catch (_:Dynamic) {
            trace("Could not clean up the backup workspace.");
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
