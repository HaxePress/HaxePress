package hx.press.plugins;

#if jvm
import java.lang.Runnable;
import hx.press.themes.ThemeMcpHost;
import hx.press.scheduling.ScheduledJobs;

@:nativeGen
class JvmPluginShutdown implements Runnable {
    public function new() {}

    public function run():Void {
        ThemeMcpHost.stop();
        ScheduledJobs.stop();
        PluginRuntime.shutdown();
    }
}
#end
