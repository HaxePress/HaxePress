package example.github;

import hx.press.plugins.PluginEntrypoint;
import hx.press.plugins.PluginHost;
import hx.well.http.ResponseBuilder;
import hx.well.route.Route;
import hx.well.route.RouteElement;

class ReleasePlugin implements PluginEntrypoint {
    var route:RouteElement;

    public function new() {}

    public function onCreate(host:PluginHost, context:String):Void {
        route = Route.get("/github-release-example", request -> ResponseBuilder.asJson({
            plugin: "github-release-example",
            status: "active"
        })).name("plugin.github-release-example.status");
    }

    public function onDestroy():Void {
        Route.unregister(route);
    }

    public function dispatch(event:String, context:String):String {
        return "{}";
    }
}
