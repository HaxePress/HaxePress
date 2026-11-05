package hx.press.plugins;

#if (cpp && !cppia)
import cpp.cppia.Module;
import haxe.Exception;
import hx.well.facades.Storage;
import haxe.io.Path;

@:headerCode('#include <hx/Scriptable.h>')
class CppiaPluginBackend implements PluginBackend {
    var module:Module;
    var instance:PluginEntrypoint;

    public function new(path:String, entrypoint:String) {
        #if !scriptable
        #error "The C++ plugin host requires -D scriptable."
        #end
        var disk = Storage.build({
            driver: "local",
            root: Path.directory(path),
            read_only: true,
            throw_errors: true
        });
        var bytecode = disk.getBytes(Path.withoutDirectory(path));
        module = Module.fromData(bytecode.getData());
        module.boot();
        var moduleClass = module.resolveClass(entrypoint);
        if (moduleClass == null) {
            throw new Exception("The CPPIA module is missing its entrypoint class.");
        }
        var created:Dynamic = Type.createInstance(moduleClass, []);
        if (!Std.isOfType(created, PluginEntrypoint)) {
            throw new Exception("The server module does not implement the CMS plugin API.");
        }
        instance = cast created;
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
        module = null;
    }
}
#end
