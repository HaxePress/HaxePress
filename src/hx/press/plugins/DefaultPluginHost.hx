package hx.press.plugins;

import hx.press.CmsAccess;
import hx.press.routes.AdminRoutes;

class DefaultPluginHost implements PluginHost {
    public function new() {}

    public function admin(routes:Void->Void):Void {
        AdminRoutes.extension(routes);
    }

    public function can(capability:String):Bool {
        return CmsAccess.can(capability);
    }
}
