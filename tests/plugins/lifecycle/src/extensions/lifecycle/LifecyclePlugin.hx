package extensions.lifecycle;

import hx.press.plugins.PluginEntrypoint;
import hx.press.plugins.PluginHost;
import haxe.Exception;
import haxe.Json;
import hx.well.http.ResponseBuilder;
import hx.well.route.Route;
import hx.well.route.RouteElement;

class LifecyclePlugin implements PluginEntrypoint {
    var routes:Array<RouteElement> = [];
    var failDestroy = false;

    public function new() {}

    public function onCreate(host:PluginHost, context:String):Void {
        var input:Dynamic = Json.parse(context);
        failDestroy = input.settings.fail_destroy == "true";
        routes.push(Route.get("/plugin-lifecycle",
            request -> ResponseBuilder.asJson({created: true}))
            .name("plugin.lifecycle.public")
            .attribute("inertia.share", false));
        host.admin(() -> {
            routes.push(Route.get("/plugin-lifecycle",
                request -> ResponseBuilder.asJson({admin: true}))
                .name("plugin.lifecycle.admin")
                .attribute("inertia.share", false));
        });
        if (input.settings.fail_create == "true") {
            throw new Exception("Requested creation failure");
        }
    }

    public function onDestroy():Void {
        if (failDestroy) {
            throw new Exception("Requested destruction failure");
        }
        for (route in routes) {
            Route.unregister(route);
        }
        routes = [];
    }

    public function dispatch(event:String, context:String):String {
        if (event == "settings.saved") {
            var input:Dynamic = Json.parse(context);
            failDestroy = input.settings.fail_destroy == "true";
        }
        return "{}";
    }
}
