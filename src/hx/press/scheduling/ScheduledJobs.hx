package hx.press.scheduling;

import haxe.Exception;
import haxe.Json;
import hx.concurrent.executor.Executor;
import hx.concurrent.executor.Schedule;
import hx.press.model.InstalledPackage;
import hx.press.model.ScheduledJob;
import hx.press.packages.PackageData;
import hx.press.packages.PackageManifest;
import hx.press.plugins.PluginRuntime;
import hx.well.database.Connection;
import hx.well.internal.SecureToken;

/** Persistent schedules share one bounded worker independent of request handling. */
class ScheduledJobs {
    public static inline var MAX_INTERVAL = 365 * 24 * 60 * 60;
    static inline var LEASE_MS = 60 * 60 * 1000;
    static final core:Map<String, Void->Void> = [];
    static var worker:Null<Executor>;

    public static function id(pluginId:Null<String>, key:String):String {
        var owner = pluginId ?? "core";
        return '${owner}:${key}';
    }

    public static function validKey(key:Null<String>):Bool {
        return key != null && ~/^[a-z0-9][a-z0-9_-]{0,63}$/.match(key);
    }

    public static function registerCore(key:String, intervalSeconds:Int, action:Void->Void):Void {
        ensure(null, key, intervalSeconds, "{}");
        core.set(id(null, key), action);
    }

    /** Re-registering the same job during plugin boot preserves its next run. */
    public static function ensure(pluginId:Null<String>, key:String, intervalSeconds:Int,
            payload:String):Void {
        var job = ScheduledJob.query.select(["interval_seconds", "payload", "enabled"])
            .where("id", id(pluginId, key))
            .limit(1)
            .first();
        if (job != null && job.interval_seconds == intervalSeconds && job.payload == payload) {
            return;
        }
        save(pluginId, key, intervalSeconds, payload, job == null || job.enabled == 1);
    }

    public static function save(pluginId:Null<String>, key:String, intervalSeconds:Int,
            payload:String, enabled:Bool, ?next:Float):Void {
        if ((pluginId != null && !PackageManifest.validPluginId(pluginId))
            || !validKey(key)
            || intervalSeconds < 1
            || intervalSeconds > MAX_INTERVAL
            || payload == null
            || payload.length > 8192) {
            throw new Exception("The schedule definition is invalid.");
        }
        var data:Dynamic = Json.parse(payload);
        if (data == null || !Reflect.isObject(data) || data is Array || data is String) {
            throw new Exception("Scheduled task data must be a JSON object.");
        }
        var now = Date.now().getTime();
        var due = next ?? now + intervalSeconds * 1000.0;
        if (!Math.isFinite(due) || due < now - 60000 || due > now + MAX_INTERVAL * 1000.0) {
            throw new Exception("Choose a valid first run for the schedule.");
        }
        ScheduledJob.query.upsert([
            "id" => id(pluginId, key),
            "plugin_id" => pluginId,
            "job_key" => key,
            "payload" => payload,
            "interval_seconds" => intervalSeconds,
            "enabled" => enabled ? 1 : 0,
            "next_epoch" => due
        ], ["id"], ["payload", "interval_seconds", "enabled", "next_epoch"]);
    }

    public static function remove(pluginId:Null<String>, key:String):Bool {
        if (!validKey(key)) {
            return false;
        }
        var identifier = id(pluginId, key);
        ScheduledJob.query.where("id", identifier)
            .where("lease_until", "<=", Date.now().getTime())
            .delete();
        return !ScheduledJob.query.where("id", identifier).exists();
    }

    public static function start():Void {
        if (worker != null) {
            return;
        }
        worker = Executor.create(1);
        worker.submit(() -> {
            try {
                runDue();
            } catch (failure:Dynamic) {
                trace('Scheduled job lookup failed: ${Std.string(failure)}');
            }
            Connection.free();
            return true;
        }, Schedule.FIXED_DELAY(3000, 1000));
    }

    public static function stop():Void {
        if (worker != null) {
            worker.stop();
        }
    }

    static function runDue():Void {
        var now = Date.now().getTime();
        var coreIds:Array<Dynamic> = [for (key in core.keys()) key];
        var activePlugins = InstalledPackage.query.select(["plugin_id"])
            .where("kind", "plugin")
            .where("enabled", 1);
        var jobs = ScheduledJob.query.where("enabled", 1)
            .where("next_epoch", "<=", now)
            .where("lease_until", "<=", now)
            .where(scope -> {
                scope.whereInQuery("plugin_id", activePlugins);
                if (coreIds.length > 0) {
                    scope.orWhere(group -> group.whereIn("id", coreIds));
                }
            })
            .orderBy("next_epoch")
            .orderBy("id")
            .limit(4)
            .get();
        for (job in jobs) {
            run(job);
        }
    }

    static function run(job:ScheduledJob):Void {
        var now = Date.now().getTime();
        var interval = job.interval_seconds * 1000.0;
        var elapsed = Math.ffloor((now - job.next_epoch) / interval);
        var next = job.next_epoch + (elapsed + 1) * interval;
        var token = SecureToken.generate(32);
        ScheduledJob.query.where("id", job.id)
            .where("enabled", 1)
            .where("next_epoch", job.next_epoch)
            .where("interval_seconds", job.interval_seconds)
            .where("payload", job.payload)
            .where("lease_until", "<=", now)
            .update(["next_epoch" => next, "lease_until" => now + LEASE_MS, "run_token" => token]);
        if (!ScheduledJob.query.where("id", job.id).where("run_token", token).exists()) {
            return;
        }
        var error = "";
        try {
            if (job.plugin_id == null) {
                core.get(job.id)();
            } else {
                var plugin = PackageData.enabledPlugin(job.plugin_id);
                if (plugin == null
                    || !PluginRuntime.runScheduled(plugin, job.id, job.job_key,
                        Json.parse(job.payload))) {
                    throw new Exception("The scheduled plugin is unavailable.");
                }
            }
        } catch (failure:Dynamic) {
            error = Std.string(failure).substr(0, 500);
        }
        ScheduledJob.query.where("id", job.id).where("run_token", token).update([
            "last_epoch" => Date.now().getTime(),
            "last_error" => error,
            "lease_until" => 0,
            "run_token" => ""
        ]);
    }
}
