package hx.press.plugins;

import haxe.Exception;
import hx.press.CmsAccess;
import hx.press.routes.AdminRoutes;
import hx.press.scheduling.ScheduledJobs;

class DefaultPluginHost implements PluginHost {
    final identity:Null<String>;

    public function new(identity:Null<String>) {
        this.identity = identity;
    }

    public function admin(routes:Void->Void):Void {
        AdminRoutes.extension(routes);
    }

    public function can(capability:String):Bool {
        return CmsAccess.can(capability);
    }

    public function schedule(pluginId:String, key:String, intervalSeconds:Int,
            ?payload:String):Void {
        requireIdentity(pluginId);
        ScheduledJobs.ensure(identity, key, intervalSeconds, payload ?? "{}");
    }

    public function unschedule(pluginId:String, key:String):Bool {
        requireIdentity(pluginId);
        return ScheduledJobs.remove(identity, key);
    }

    function requireIdentity(pluginId:String):Void {
        if (identity == null || pluginId != identity) {
            throw new Exception("A scheduled task must use its installed plugin ID.");
        }
    }
}
