package hx.press.plugins;

#if php
import haxe.Exception;
import haxe.io.Path;
import hx.well.facades.Storage;
import php.Global;
import php.Syntax;
import php.reflection.ReflectionClass;

class PhpPluginBackend implements PluginBackend {
    var instance:PluginEntrypoint;
    var autoload:String->Void;

    public function new(path:String, entrypoint:String) {
        var disk = Storage.build({
            driver: "local",
            root: Path.directory(path),
            read_only: true,
            throw_errors: true
        });
        var definition = PhpModuleDefinition.inspect(disk, Path.withoutDirectory(path), entrypoint);
        autoload = name -> {
            var file = definition.classes.get(name);
            if (file != null) {
                // PHP inclusion is a native runtime boundary, after Storage validates the path.
                Global.require_once(disk.path(file));
            }
        };
        Global.spl_autoload_register(autoload);
        try {
            var moduleClass = new ReflectionClass(definition.entrypoint);
            if (!moduleClass.implementsInterface(Syntax.nativeClassName(PluginEntrypoint))) {
                throw new Exception("The server module does not implement the CMS plugin API.");
            }
            var created:Dynamic = moduleClass.newInstance();
            instance = cast created;
        } catch (error:Dynamic) {
            close();
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
        if (autoload != null) {
            Global.spl_autoload_unregister(autoload);
            autoload = null;
        }
    }
}
#end
