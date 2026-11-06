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
    var scheduledRuns = 0;

    public function new() {}

    public function onCreate(host:PluginHost, context:String):Void {
        var input:Dynamic = Json.parse(context);
        failDestroy = input.settings.fail_destroy == "true";
        if (input.settings.schedule_probe == "true") {
            var denied = false;
            try {
                host.schedule("4731896a-89e5-4321-bdb1-565f752d3fb5", "probe", 60);
            } catch (_:Exception) {
                denied = true;
            }
            if (!denied) {
                throw new Exception("The plugin registered a job with another identity.");
            }
            host.schedule(input.packageInfo.pluginId, "probe", 60, '{"marker":"lifecycle"}');
        }
        routes.push(Route.get("/plugin-lifecycle",
            request -> ResponseBuilder.asJson({created: true, scheduledRuns: scheduledRuns}))
            .name("plugin.lifecycle.public"));
        host.admin(() -> {
            routes.push(Route.get("/plugin-lifecycle", request -> ResponseBuilder.asJson({
                admin: true,
                echo: request.query("message", "")
            })).name("plugin.lifecycle.admin").attribute("cms.mcp", {
                name: "status",
                description: "Read the lifecycle fixture and echo a short message.",
                capability: "extensions",
                inputSchema: {
                    type: "object",
                    properties: {message: {type: "string", maxLength: 80}}
                }
            }));
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
        if (event == "schedule.run") {
            var input:Dynamic = Json.parse(context);
            if (input.data.key == "probe" && input.data.payload.marker == "lifecycle") {
                scheduledRuns++;
            }
        }
        return "{}";
    }
}
