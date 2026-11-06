package hx.press.plugins;

import hx.press.ContentCache;
import hx.press.model.InstalledPackage;

class PluginHealth {
    public static var restartRequired(default, null):Bool = false;

    public static function beginBoot():Void {
        restartRequired = false;
        if (InstalledPackage.query.select(["id"]).where("restart_required", 1).exists()) {
            InstalledPackage.query.where("restart_required", 1).update(["restart_required" => 0]);
            ContentCache.changed("extensions");
        }
    }

    public static function failed(id:String, directory:String, phase:String, error:Dynamic):Void {
        restartRequired = true;
        var message = 'Plugin ${phase} failed: ${Std.string(error)}';
        InstalledPackage.query.where("id", id)
            .where("directory", directory)
            .update(["enabled" => 0, "restart_required" => 1, "last_error" => message.substr(0,
                2000)]);
        ContentCache.changed("extensions");
    }
}
