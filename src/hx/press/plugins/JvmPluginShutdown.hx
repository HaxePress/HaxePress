package hx.press.plugins;

#if jvm
import java.lang.Runnable;
import hx.press.themes.ThemePreviewBrowser;
import hx.press.scheduling.ScheduledJobs;

@:nativeGen
class JvmPluginShutdown implements Runnable {
    public function new() {}

    public function run():Void {
        ThemePreviewBrowser.stop();
        ScheduledJobs.stop();
        PluginRuntime.shutdown();
    }
}
#end
