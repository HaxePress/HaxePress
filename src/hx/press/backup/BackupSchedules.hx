package hx.press.backup;

#if jvm
import haxe.Exception;
import haxe.Json;
import haxe.crypto.Sha256;
import hx.press.AdminController;
import hx.press.CmsVersion;
import hx.press.backup.SiteBackupArchive.BackupSelection;
import hx.press.model.ScheduledBackup;
import hx.press.model.ScheduledJob;
import hx.press.packages.BuiltInPlugins;
import hx.press.scheduling.ScheduledJobs;
import hx.press.view.View;
import hx.well.facades.Storage;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.ResponseBuilder;
import hx.well.http.ResponseStatic.abort;
import hx.well.internal.SecureToken;

private typedef ScheduleInput = {
    var name:String;
    var interval:Int;
    var retain:Int;
    var enabled:Bool;
    var firstRun:Null<Float>;
    var encrypted:Bool;
    var content:Bool;
    var themes:Bool;
    var plugins:Bool;
}

typedef BackupArchive = {
    var id:String;
    var createdAt:Float;
    var cmsVersion:String;
    var encrypted:Bool;
    var size:Int;
    var md5:String;
    var download:String;
}

private typedef BackupPolicy = {
    var name:String;
    var sections:BackupSelection;
    var encrypted:Bool;
    var retain:Int;
}

class BackupSchedules {
    static inline var OWNER = BuiltInPlugins.BACKUP_IDENTITY;
    static inline var DIRECTORY = "scheduled-backups";
    static inline var MAX_SCHEDULES = 24;
    static inline var MAX_RETENTION = 50;

    public static function list():Array<Dynamic> {
        var jobs = ScheduledJob.query.select([
            "job_key",
            "payload",
            "interval_seconds",
            "enabled",
            "next_epoch",
            "last_epoch",
            "last_error",
            "lease_until"
        ]).where("plugin_id", OWNER).orderBy("next_epoch").orderBy("id").limit(MAX_SCHEDULES).get();
        var now = Date.now().getTime();
        return jobs.map(job -> {
            var policy = options(job.payload);
            return {
                id: job.job_key,
                name: policy.name,
                sections: policy.sections,
                encrypted: policy.encrypted,
                retain: policy.retain,
                intervalSeconds: job.interval_seconds,
                enabled: job.enabled == 1,
                nextRun: job.next_epoch,
                lastRun: job.last_epoch,
                lastError: job.last_error,
                running: job.lease_until > now
            };
        });
    }

    public static function save(request:Request):AbstractResponse {
        SiteBackup.requireAccess();
        if (!SiteBackup.supported()) {
            return error("Site backups require SQLite or MySQL.");
        }
        var key = request.route("key");
        var formUrl = '${SiteBackup.PATH}?schedule=${key ?? "new"}';
        var input = scheduleInput(request);
        if (input == null) {
            return rejected(request, "Check the backup schedule, interval and retention.", formUrl);
        }
        var name = input.name;
        var sections:BackupSelection = {
            content: input.content,
            themes: input.themes,
            plugins: input.plugins
        };
        if (name == "" || (!sections.content && !sections.themes && !sections.plugins)) {
            return rejected(request, "Name the schedule and choose at least one backup section.",
                formUrl);
        }
        var interval = input.interval;
        var firstRun = input.firstRun;
        if (key == null) {
            if (ScheduledJob.query.where("plugin_id", OWNER).count() >= MAX_SCHEDULES) {
                return rejected(request, "You can create up to 24 backup schedules.", formUrl);
            }
            var token = Sha256.encode(SecureToken.generate(24)).substr(0, 24);
            key = 'backup-${token}';
        } else {
            var existing = ScheduledJob.query.select(["interval_seconds", "next_epoch"])
                .where("id", ScheduledJobs.id(OWNER, key))
                .where("plugin_id", OWNER)
                .limit(1)
                .first();
            if (existing == null) {
                abort(404);
            }
            if (firstRun == null && existing.interval_seconds == interval
                && existing.next_epoch > Date.now().getTime()) {
                firstRun = existing.next_epoch;
            }
        }
        var policy:BackupPolicy = {
            name: name,
            sections: sections,
            encrypted: input.encrypted,
            retain: input.retain
        };
        try {
            ScheduledJobs.save(OWNER, key, interval, Json.stringify(policy), input.enabled,
                firstRun);
            prune(ScheduledJobs.id(OWNER, key), policy.retain);
            if (View.redirectsValidation(request)) {
                return ResponseBuilder.asRedirect(SiteBackup.PATH, 303);
            }
            return json({saved: true, id: key});
        } catch (failure:Dynamic) {
            return rejected(request, Std.string(failure), formUrl);
        }
    }

    /**
        The schedule fields of a JSON request, or of the schedule form, which
        posts text: an interval as a count and a unit, check boxes as `1`
        and the first run as epoch milliseconds (empty for one interval).
    **/
    static function scheduleInput(request:Request):Null<ScheduleInput> {
        var contentType = request.header("Content-Type", "");
        if (contentType.indexOf("application/x-www-form-urlencoded") < 0) {
            if (!request.validate([
                "name" => [Required, String, Max(100)],
                "intervalSeconds" => [Required, Int, Min(60), Max(ScheduledJobs.MAX_INTERVAL)],
                "retain" => [Required, Int, Min(1), Max(MAX_RETENTION)],
                "enabled" => [Required, Bool],
                "firstRun" => [Number],
                "encrypted" => [Required, Bool],
                "content" => [Required, Bool],
                "themes" => [Required, Bool],
                "plugins" => [Required, Bool]
            ])) {
                return null;
            }
            return {
                name: StringTools.trim(request.input("name")),
                interval: request.input("intervalSeconds"),
                retain: request.input("retain"),
                enabled: request.input("enabled"),
                firstRun: request.input("firstRun"),
                encrypted: request.input("encrypted"),
                content: request.input("content"),
                themes: request.input("themes"),
                plugins: request.input("plugins")
            };
        }
        var name = StringTools.trim(field(request, "name"));
        var every = Std.parseInt(field(request, "every"));
        var unit = Std.parseInt(field(request, "period"));
        var retain = Std.parseInt(field(request, "retain"));
        var firstRunText = field(request, "firstRun");
        var firstRun:Null<Float> = firstRunText == "" ? null : Std.parseFloat(firstRunText);
        if (name.length > 100
            || every == null
            || unit == null
            || retain == null
            || ![60, 3600, 86400, 604800].contains(unit)
            || every < 1
            || every * 1.0 * unit > ScheduledJobs.MAX_INTERVAL
            || retain < 1
            || retain > MAX_RETENTION
            || (firstRun != null && !Math.isFinite(firstRun))) {
            return null;
        }
        return {
            name: name,
            interval: every * unit,
            retain: retain,
            enabled: field(request, "enabled") == "1",
            firstRun: firstRun,
            encrypted: field(request, "encrypted") == "1",
            content: field(request, "content") == "1",
            themes: field(request, "themes") == "1",
            plugins: field(request, "plugins") == "1"
        };
    }

    static function field(request:Request, key:String):String {
        var value:Dynamic = request.input(key, "");
        return Std.isOfType(value, String) ? value : "";
    }

    /** A refused schedule change: the backups page with the error for forms, JSON otherwise. **/
    static function rejected(request:Request, message:String, url:String,
            scope:String = "schedule", status:Int = 422):AbstractResponse {
        var redirect = AdminController.validationRedirect(request, scope, message, url);
        return redirect ?? error(message, status);
    }

    public static function remove(request:Request):AbstractResponse {
        SiteBackup.requireAccess();
        var key = request.route("key");
        var id = requireSchedule(key);
        var now = Date.now().getTime();
        ScheduledJob.query.where("id", id).where("lease_until", "<=", now).update(["enabled" => 0]);
        var running = "Wait for the running backup before deleting this schedule.";
        if (ScheduledJob.query.where("id", id).where("lease_until", ">", now).exists()) {
            return rejected(request, running, SiteBackup.PATH, "schedules", 409);
        }
        try {
            prune(id, 0);
            if (!ScheduledJobs.remove(OWNER, key)) {
                return rejected(request, running, SiteBackup.PATH, "schedules", 409);
            }
            if (View.redirectsValidation(request)) {
                return ResponseBuilder.asRedirect(SiteBackup.PATH, 303);
            }
            return json({deleted: true});
        } catch (failure:Dynamic) {
            return rejected(request, Std.string(failure), SiteBackup.PATH, "schedules");
        }
    }

    public static function files(request:Request):AbstractResponse {
        SiteBackup.requireAccess();
        return json({archives: archives(request.route("key"))});
    }

    /** The saved backups of a schedule, newest first. **/
    public static function archives(key:String):Array<BackupArchive> {
        var id = requireSchedule(key);
        var rows = ScheduledBackup.query.select(["id", "created_epoch", "cms_version", "encrypted", "size", "md5"])
            .where("schedule_id", id)
            .orderBy("created_epoch", "DESC")
            .orderBy("id", "DESC")
            .limit(MAX_RETENTION)
            .get();
        var archives = rows.map(file -> {
            var archive:BackupArchive = {
                id: file.id,
                createdAt: file.created_epoch,
                cmsVersion: file.cms_version,
                encrypted: file.encrypted == 1,
                size: file.size,
                md5: file.md5,
                download: '${SiteBackup.PATH}/scheduled-downloads/${file.id}'
            };
            return archive;
        });
        return archives;
    }

    public static function download(request:Request):AbstractResponse {
        SiteBackup.requireAccess();
        var id = request.route("file");
        if (id == null || !~/^[A-Za-z0-9_-]{32}$/.match(id)) {
            abort(404);
        }
        var schedules = ScheduledJob.query.select(["id"]).where("plugin_id", OWNER);
        var file = ScheduledBackup.query.select(["created_epoch"])
            .where("id", id)
            .whereInQuery("schedule_id", schedules)
            .limit(1)
            .first();
        var disk = Storage.disk("exports");
        var path = archivePath(id);
        if (file == null || !disk.fileExists(path)) {
            abort(404);
        }
        var timestamp = DateTools.format(Date.fromTime(file.created_epoch), "%Y-%m-%d-%H%M");
        var filename = 'haxepress-scheduled-${timestamp}-${id.substr(0, 8)}.${BackupFormat.EXTENSION}';
        return disk.download(path, filename, [
            "Content-Type" => "application/octet-stream",
            "Cache-Control" => "private, no-store"
        ]);
    }

    public static function run(context:Dynamic):Void {
        var job = ScheduledJob.query.select(["id", "payload"])
            .where("id", context.id)
            .where("plugin_id", OWNER)
            .where("enabled", 1)
            .limit(1)
            .first();
        if (job == null) {
            return;
        }
        var policy = options(job.payload);
        var id = SecureToken.generate(32);
        var disk = Storage.disk("exports");
        var path = archivePath(id);
        try {
            var md5 = SiteBackup.createArchive(disk, path, policy.sections, policy.encrypted);
            ScheduledBackup.query.insert([
                "id" => id,
                "schedule_id" => job.id,
                "created_epoch" => Date.now().getTime(),
                "cms_version" => CmsVersion.version,
                "encrypted" => policy.encrypted ? 1 : 0,
                "size" => disk.size(path),
                "md5" => md5
            ]);
        } catch (failure:Dynamic) {
            disk.delete(path);
            throw failure;
        }
        prune(job.id, policy.retain);
    }

    static function prune(scheduleId:String, retain:Int):Void {
        var keep:Array<Dynamic> = [];
        if (retain > 0) {
            keep = ScheduledBackup.query.select(["id"])
                .where("schedule_id", scheduleId)
                .orderBy("created_epoch", "DESC")
                .orderBy("id", "DESC")
                .limit(retain)
                .get()
                .map(file -> (file.id : Dynamic));
        }
        var disk = Storage.disk("exports");
        while (true) {
            var old = ScheduledBackup.query.select(["id"])
                .where("schedule_id", scheduleId)
                .whereNotIn("id", keep)
                .orderBy("id")
                .limit(16)
                .get();
            if (old.length == 0) {
                return;
            }
            for (file in old) {
                disk.delete(archivePath(file.id));
                file.delete();
            }
        }
    }

    static function archivePath(id:String):String {
        return '${DIRECTORY}/${id}.${BackupFormat.EXTENSION}';
    }

    static function requireSchedule(key:String):String {
        var id = ScheduledJobs.id(OWNER, key);
        if (!ScheduledJobs.validKey(key)
            || !ScheduledJob.query.where("id", id).where("plugin_id", OWNER).exists()) {
            abort(404);
        }
        return id;
    }

    static function options(payload:String):BackupPolicy {
        return cast Json.parse(payload);
    }

    static function json(data:Dynamic, status:Int = 200):AbstractResponse {
        return ResponseBuilder.asJson(data, status).header("Cache-Control", "private, no-store");
    }

    static function error(message:String, status:Int = 422):AbstractResponse {
        return json({error: message}, status);
    }
}
#end
