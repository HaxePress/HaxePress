package hx.press.backup;

#if jvm
import haxe.ds.StringMap;
import hx.press.i18n.I18n;
import hx.press.view.View;
import hx.well.http.Request;

private typedef BackupPeriod = {
    var label:String;
    var singular:String;
    var seconds:Int;
}

/**
    Presentation data of `Admin/Backups`: schedule summaries, the schedule
    form opened with `?schedule=new|<id>`, the saved files listed with
    `?files=<id>` and the manual backup form with its verified result.
**/
class BackupViews {
    static final periods:Array<BackupPeriod> = [
        {label: "Weeks", singular: "Week", seconds: 604800},
        {label: "Days", singular: "Day", seconds: 86400},
        {label: "Hours", singular: "Hour", seconds: 3600},
        {label: "Minutes", singular: "Minute", seconds: 60}
    ];
    static final sectionLabels = ["content" => "Content", "themes" => "Themes", "plugins" => "Plugins"];
    static final sectionKeys = ["content", "themes", "plugins"];

    static inline var YEAR_SECONDS = 31536000;

    /** `YYYY-MM-DD HH:MM UTC`, as the schedule list showed before. **/
    public static function dateLabel(epoch:Float):String {
        var date = Date.fromTime(epoch);
        var month = StringTools.lpad(Std.string(date.getUTCMonth() + 1), "0", 2);
        var day = StringTools.lpad(Std.string(date.getUTCDate()), "0", 2);
        var hours = StringTools.lpad(Std.string(date.getUTCHours()), "0", 2);
        var minutes = StringTools.lpad(Std.string(date.getUTCMinutes()), "0", 2);
        return '${date.getUTCFullYear()}-${month}-${day} ${hours}:${minutes} UTC';
    }

    static function periodFor(interval:Int):BackupPeriod {
        for (period in periods) {
            if (interval % period.seconds == 0) {
                return period;
            }
        }
        return periods[periods.length - 1];
    }

    /** The schedules with their summary and status lines in the current locale. **/
    public static function schedules(list:Array<Dynamic>):Array<Dynamic> {
        var encrypted = I18n.t("Encrypted");
        for (schedule in list) {
            var interval:Int = schedule.intervalSeconds;
            var period = periodFor(interval);
            var count = Std.int(interval / period.seconds);
            var unit = I18n.t(count == 1 ? period.singular : period.label).toLowerCase();
            var every = I18n.t("Every {count} {period}", ["count" => count, "period" => unit]);
            var sections:Dynamic = schedule.sections;
            var names = [
                for (key in sectionKeys)
                    if (Reflect.field(sections, key) == true) I18n.t(sectionLabels.get(key))
            ];
            var keep = I18n.t("Keep {count}", ["count" => schedule.retain]);
            var lock = schedule.encrypted == true ? ' · ${encrypted}' : "";
            schedule.summaryLabel = '${every} · ${names.join(", ")} · ${keep}${lock}';
            var status = I18n.t("Paused");
            if (schedule.running == true) {
                status = I18n.t("Backup in progress");
            } else if (schedule.enabled == true) {
                status = I18n.t("Next run {time}", ["time" => dateLabel(schedule.nextRun)]);
            }
            var lastRun:Float = schedule.lastRun;
            if (lastRun > 0) {
                var last = I18n.t("Last run {time}", ["time" => dateLabel(lastRun)]);
                status = '${status} · ${last}';
            }
            schedule.statusLabel = status;
        }
        return list;
    }

    /** The schedule form for `?schedule=new` or an existing schedule, with a failed save's input. **/
    public static function scheduleForm(request:Request, list:Array<Dynamic>):Null<Dynamic> {
        var key = request.query("schedule", "");
        if (key == "") {
            return null;
        }
        var schedule:Dynamic = null;
        for (candidate in list) {
            if (candidate.id == key) {
                schedule = candidate;
            }
        }
        if (key != "new" && schedule == null) {
            return null;
        }
        var interval:Int = schedule == null ? 86400 : schedule.intervalSeconds;
        var period = periodFor(interval);
        var sections:Dynamic = schedule == null ? {
            content: true,
            themes: true,
            plugins: true
        } : schedule.sections;
        var form = {
            id: schedule == null ? "" : schedule.id,
            action: schedule == null ? '${SiteBackup.PATH}/schedules' : '${SiteBackup.PATH}/schedules/${schedule.id}',
            name: schedule == null ? "" : schedule.name,
            every: Std.int(interval / period.seconds),
            everyMaximum: Std.int(YEAR_SECONDS / 60),
            periods: [],
            retain: schedule == null ? 5 : schedule.retain,
            content: sections.content == true,
            themes: sections.themes == true,
            plugins: sections.plugins == true,
            encrypted: schedule != null && schedule.encrypted == true,
            enabled: schedule == null || schedule.enabled == true};
        var periodSeconds = period.seconds;
        var submitted = old(request);
        if (submitted != null) {
            form.name = text(submitted, "name");
            form.every = number(submitted, "every", form.every);
            periodSeconds = number(submitted, "period", periodSeconds);
            form.retain = number(submitted, "retain", form.retain);
            form.content = submitted.get("content") == "1";
            form.themes = submitted.get("themes") == "1";
            form.plugins = submitted.get("plugins") == "1";
            form.encrypted = submitted.get("encrypted") == "1";
            form.enabled = submitted.get("enabled") == "1";
        }
        form.periods = [
            for (choice in periods)
                {
                    seconds: choice.seconds,
                    label: choice.label,
                    selected: choice.seconds == periodSeconds
                }
        ];
        return form;
    }

    /** The saved backups of the schedule named by `?files=`. **/
    public static function savedFiles(request:Request, list:Array<Dynamic>):Null<Dynamic> {
        var key = request.query("files", "");
        var schedule:Dynamic = null;
        for (candidate in list) {
            if (key != "" && candidate.id == key) {
                schedule = candidate;
            }
        }
        if (schedule == null) {
            return null;
        }
        var encrypted = I18n.t("Encrypted");
        var archives = BackupSchedules.archives(key).map(archive -> {
            var kilobytes = Std.int(Math.max(1, Math.round(archive.size / 1024)));
            var lock = archive.encrypted ? ' · ${encrypted}' : "";
            return {
                id: archive.id,
                createdLabel: dateLabel(archive.createdAt),
                detailsLabel: 'HaxePress ${archive.cmsVersion} · ${kilobytes} KB${lock}',
                md5: archive.md5,
                download: archive.download
            };
        });
        return {name: schedule.name, archives: archives};
    }

    /** The manual backup form: the sections last submitted and a verified download. **/
    public static function backupForm(request:Request):Dynamic {
        var form = {
            content: true,
            themes: true,
            plugins: true,
            encrypted: false,
            download: "",
            md5: ""
        };
        var submitted = old(request);
        if (submitted != null && submitted.get("backup_form") == "1") {
            form.content = submitted.get("content") == "1";
            form.themes = submitted.get("themes") == "1";
            form.plugins = submitted.get("plugins") == "1";
            form.encrypted = submitted.get("encrypted") == "1";
        }
        var verified:Dynamic = View.flashed(request, "backup");
        if (verified != null) {
            form.download = verified.download;
            form.md5 = verified.md5;
        }
        return form;
    }

    static function old(request:Request):Null<Map<String, Dynamic>> {
        var flashed:Dynamic = View.flashed(request, "old");
        return Std.isOfType(flashed, StringMap) ? cast flashed : null;
    }

    static function text(values:Map<String, Dynamic>, key:String):String {
        var value:Dynamic = values.get(key);
        return Std.isOfType(value, String) ? value : "";
    }

    static function number(values:Map<String, Dynamic>, key:String, fallback:Int):Int {
        var parsed = Std.parseInt(text(values, key));
        return parsed == null ? fallback : parsed;
    }
}
#end
