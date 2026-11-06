package hx.press.provider;

import hx.press.ContentWorkflow;
import hx.press.WorkingCopies;
import hx.press.media.ImageUploads;
import hx.press.packages.PackageManager;
import hx.press.plugins.PluginRuntime;
import hx.press.themes.ThemeMcpHost;
import hx.well.database.Connection;
import hx.well.facades.Cache;
import hx.well.facades.Schedule;
import hx.well.facades.Storage;
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
        Schedule.get().fixedDelay(_ -> {
            Cache.store().expireCache();
            try {
                ImageUploads.expire();
                PackageManager.cleanupUploads();
                WorkingCopies.expire();
                Connection.free();
            } catch (error:Dynamic) {
                Connection.free();
                trace("Temporary upload cleanup failed: " + Std.string(error));
            }
            return true;
        }, 60000, 60000);
        Schedule.get().fixedDelay(_ -> {
            try {
                ContentWorkflow.publishDue();
                Connection.free();
            } catch (error:Dynamic) {
                Connection.free();
                trace("Scheduled publishing failed: " + Std.string(error));
            }
            return true;
        }, 5000, 5000);
        PluginRuntime.boot();
        ThemeMcpHost.start();
        Connection.free();
        #if jvm
        JavaRuntime.getRuntime().addShutdownHook(new JavaThread(new JvmPluginShutdown()));
        #end
    }
}
