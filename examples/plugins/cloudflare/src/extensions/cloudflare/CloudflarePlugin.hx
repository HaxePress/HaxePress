package extensions.cloudflare;

import haxe.Json;
import hx.press.plugins.PluginEntrypoint;
import hx.press.plugins.PluginHost;
import hx.press.plugins.PluginMiddleware;

/**
    Takes each visitor's address from Cloudflare's `CF-Connecting-IP`
    header, through a middleware that runs while the plugin is active.
**/
class CloudflarePlugin implements PluginEntrypoint {
    var middleware:PluginMiddleware;

    public function new() {}

    public function onCreate(host:PluginHost, context:String):Void {
        configure(context);
        middleware = PluginMiddleware.add(CloudflareMiddleware);
    }

    public function onDestroy():Void {
        PluginMiddleware.remove(middleware);
    }

    public function dispatch(event:String, context:String):String {
        if (event == "settings.saved") {
            configure(context);
        }
        return "{}";
    }

    static function configure(context:String):Void {
        var input:Dynamic = Json.parse(context);
        var settings:Dynamic = input.settings;
        var tunnel:Dynamic = settings == null ? null : settings.tunnel;
        CloudflareMiddleware.tunnel = tunnel == "true";
    }
}
