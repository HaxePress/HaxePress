package hx.press.plugins;

#if jvm
import java.lang.Runnable;
import hx.press.themes.ThemeMcpHost;

@:nativeGen
class JvmPluginShutdown implements Runnable {
    public function new() {}

    public function run():Void {
        ThemeMcpHost.stop();
        PluginRuntime.shutdown();
    }
}
#end
