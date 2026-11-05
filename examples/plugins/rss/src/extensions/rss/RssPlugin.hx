package extensions.rss;

import hx.press.plugins.PluginEntrypoint;
import hx.press.plugins.PluginHost;
import haxe.Json;
import hx.press.i18n.I18n;
import hx.well.route.Route;
import hx.well.route.RouteElement;

class RssPlugin implements PluginEntrypoint {
    var route:RouteElement;

    public function new() {}

    public function onCreate(host:PluginHost, context:String):Void {
        route = Route.get("/rss.xml", new RssHandler())
            .name("plugin.rss.feed")
            .attribute("inertia.share", false);
    }

    public function onDestroy():Void {
        Route.unregister(route);
    }

    public function dispatch(event:String, context:String):String {
        var input:Dynamic = Json.parse(context);
        if (event == "ui.navigation" && input.data.location == "footer") {
            var label = I18n.t("RSS", null, "plugin-rss");
            return Json.stringify({items: [{label: label, href: "/rss.xml", icon: "rss"}]});
        }
        return "{}";
    }
}
