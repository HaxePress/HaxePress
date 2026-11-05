package hx.press.plugins;

#if jvm
import haxe.Exception;
import java.net.URI;
import java.net.URL;
import java.net.URLClassLoader;
import java.NativeArray;

using jvm.NativeTools.NativeClassTools;

class JvmPluginBackend implements PluginBackend {
    var loader:URLClassLoader;
    var instance:PluginEntrypoint;

    public function new(path:String, entrypoint:String) {
        var api = PluginEntrypoint.native();
        var urls = new NativeArray<URL>(1);
        urls[0] = new URI("file", null, path, null).toURL();
        loader = new PluginClassLoader(urls, api.getClassLoader());
        try {
            var moduleClass = loader.loadClass(entrypoint);
            if (!api.isAssignableFrom(moduleClass) || moduleClass.getClassLoader() != loader) {
                throw new Exception("The server module does not implement the CMS plugin API.");
            }
            var created:Dynamic = Type.createInstance(moduleClass.haxe(), []);
            if (created == null) {
                throw new Exception("The server module requires a public constructor with no arguments.");
            }
            instance = cast created;
        } catch (error:Dynamic) {
            loader.close();
            throw error;
        }
    }

    public function create(host:PluginHost, context:String):Void {
        instance.onCreate(host, context);
    }

    public function destroy():Void {
        instance.onDestroy();
    }

    public function dispatch(event:String, context:String):String {
        if (instance == null) {
            throw new Exception("This plugin module has been closed.");
        }
        return instance.dispatch(event, context);
    }

    public function close():Void {
        instance = null;
        loader.close();
    }
}
#end
