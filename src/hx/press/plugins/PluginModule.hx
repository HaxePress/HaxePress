package hx.press.plugins;

import hx.press.packages.PackageManifest;
import haxe.Exception;
import haxe.Json;

class PluginModule {
    var backend:PluginBackend;
    var creationStarted = false;
    var destroyed = false;

    public function new(path:String, entrypoint:String) {
        #if jvm
        backend = new JvmPluginBackend(path, entrypoint);
        #elseif (cpp && !cppia)
        backend = new CppiaPluginBackend(path, entrypoint);
        #elseif php
        backend = new PhpPluginBackend(path, entrypoint);
        #else
        throw new Exception("Server plugins require a JVM, C++ or PHP host.");
        #end
    }

    public function dispatch(event:String, context:Dynamic):Dynamic {
        var lifecycle = [
            "install",
            "activate",
            "deactivate",
            "uninstall",
            "settings.saved",
            "schedule.run",
            "installation.panel"
        ];
        if (!PackageManifest.events.contains(event) && !lifecycle.contains(event)) {
            throw new Exception("The requested plugin hook is not supported.");
        }
        var response = backend.dispatch(event, Json.stringify(context));
        if (response == null || StringTools.trim(response) == "") {
            return {};
        }
        if (response.length > 65536) {
            throw new Exception("The server module returned more than 64 KB of data.");
        }
        var data:Dynamic = Json.parse(response);
        if (data == null
            || !Reflect.isObject(data)
            || Std.isOfType(data, String)
            || Std.isOfType(data, Array)) {
            throw new Exception("Server plugin hooks must return JSON objects.");
        }
        return data;
    }

    public function create(host:PluginHost, context:Dynamic):Void {
        if (creationStarted) {
            throw new Exception("This plugin instance has already been created.");
        }
        creationStarted = true;
        backend.create(host, Json.stringify(context));
    }

    public function destroy():Void {
        if (!creationStarted || destroyed) {
            return;
        }
        destroyed = true;
        backend.destroy();
    }

    public function close():Void {
        backend.close();
    }
}
