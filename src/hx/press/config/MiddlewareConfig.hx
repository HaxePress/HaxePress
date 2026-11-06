package hx.press.config;

import hx.well.config.IConfig;
#if !cms_plugin
import hx.press.middleware.SecurityMiddleware;
import hx.press.install.InstallationMiddleware;
import hx.press.middleware.LocaleMiddleware;
#end
import hx.well.middleware.DatabaseMiddleware;
import hx.well.middleware.AbstractMiddleware;

class MiddlewareConfig implements IConfig {
    public function new() {}

    public function get():Array<Class<AbstractMiddleware>> {
        #if cms_plugin
        return [];
        #else
        return [InstallationMiddleware, DatabaseMiddleware, SecurityMiddleware, LocaleMiddleware];
        #end
    }
}
