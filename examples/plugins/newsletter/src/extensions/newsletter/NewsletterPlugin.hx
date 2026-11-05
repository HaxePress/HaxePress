package extensions.newsletter;

import hx.press.plugins.PluginEntrypoint;
import hx.press.plugins.PluginHost;
import hx.press.plugins.PluginDatabase;
import hx.press.plugins.PluginMigration;
import haxe.Json;
import hx.press.i18n.I18n;
import hx.well.facades.Schema;
import hx.well.route.Route;
import hx.well.route.RouteElement;

using hx.well.tools.RouteElementTools;

class NewsletterPlugin implements PluginEntrypoint {
    var routes:Array<RouteElement> = [];
    var host:PluginHost;

    public function new() {}

    public function onCreate(host:PluginHost, context:String):Void {
        this.host = host;
        var database = new PluginDatabase("newsletter");
        database.migrate([
            new PluginMigration("001_create_subscribers", () -> {
                if (!Schema.hasTable("subscribers")) {
                    Schema.create("subscribers", table -> {
                        table.id();
                        table.string("email").unique();
                        table.dateTime("created_at");
                    });
                }
            })
        ]);
        routes.push(Route.post("/subscribe", new SubscribeHandler())
            .attribute("inertia.share", false));
        host.admin(() -> {
            routes.push(Route.get("/subscribers", new ListSubscribersHandler(host)));
            routes.push(Route.get("/subscribers/export", new ExportSubscribersHandler(host))
                .attribute("inertia.share", false));
            routes.push(Route.post("/subscribers/{id}/delete", new DeleteSubscriberHandler(host))
                .whereNumber("id"));
        });
    }

    public function onDestroy():Void {
        for (route in routes) {
            Route.unregister(route);
        }
        routes = [];
    }

    public function dispatch(event:String, context:String):String {
        var input:Dynamic = Json.parse(context);
        if (event == "ui.navigation") {
            if (input.data.location == "admin" && host.can("subscribers")) {
                return Json.stringify({
                    items: [
                        {
                            label: I18n.t("Subscribers", null, "plugin-newsletter"),
                            href: "/admin/subscribers",
                            icon: "mail"
                        }
                    ]
                });
            }
            if (input.data.location == "header") {
                return Json.stringify({
                    items: [
                        {
                            label: I18n.t("Subscribe", null, "plugin-newsletter"),
                            href: "/#newsletter",
                            icon: "arrow-up-right"
                        }
                    ]
                });
            }
        }
        if (event == "dashboard.widgets" && host.can("subscribers")) {
            var count = SubscriberData.count();
            var heading = I18n.t("Newsletter", null, "plugin-newsletter");
            var summary = I18n.t("{count} subscribers. [Manage subscribers](/admin/subscribers).",
                ["count" => count], "plugin-newsletter");
            return Json.stringify({
                blocks: [
                    {
                        slot: "dashboard",
                        content: "### " + heading + "\n\n" + summary
                    }
                ]
            });
        }
        return "{}";
    }
}
