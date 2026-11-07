package hx.press.provider;

import hx.press.ContentWorkflow;
import hx.press.MediaCatalog;
import hx.press.ai.AdminMcpAccess;
import hx.press.WorkingCopies;
import hx.press.media.ImageUploads;
import hx.press.packages.PackageManager;
import hx.press.plugins.PluginRuntime;
import hx.press.scheduling.ScheduledJobs;
import hx.well.database.Connection;
import hx.well.facades.Cache;
import hx.well.facades.Storage;
#if php
import hx.press.scheduling.RunScheduleCommand;
import hx.well.console.CommandExecutor;
#else
import hx.well.facades.Schedule;
#end
#if jvm
import hx.press.plugins.JvmPluginShutdown;
import java.lang.Runtime as JavaRuntime;
import java.lang.Thread as JavaThread;
#end

class SiteRuntime {
    static var started = false;

    public static function start():Void {
        if (started) {
            return;
        }
        started = true;
        Storage.disk("media").makeDirectory("");
        ScheduledJobs.registerCore("temporary-files", 60, () -> {
            Cache.store().expireCache();
            ImageUploads.expire();
            PackageManager.cleanupUploads();
            WorkingCopies.expire();
            AdminMcpAccess.cleanup();
        });
        ScheduledJobs.registerCore("media-trash", 3600, () -> {
            MediaCatalog.purgeTrash();
        });
        #if php
        // Each PHP request is a new process, so publishing runs as a leased job.
        ScheduledJobs.registerCore("scheduled-publishing", 60, () -> {
            ContentWorkflow.publishDue();
        });
        CommandExecutor.register(cast RunScheduleCommand);
        #else
        Schedule.get().fixedDelay(_ -> {
            try {
                ContentWorkflow.publishDue();
                Connection.free();
            } catch (error:Dynamic) {
                Connection.free();
                trace('Scheduled publishing failed: ${Std.string(error)}');
            }
            return true;
        }, 5000, 5000);
        #end
        PluginRuntime.boot();
        ScheduledJobs.start();
        Connection.free();
        #if jvm
        JavaRuntime.getRuntime().addShutdownHook(new JavaThread(new JvmPluginShutdown()));
        #end
    }
}
