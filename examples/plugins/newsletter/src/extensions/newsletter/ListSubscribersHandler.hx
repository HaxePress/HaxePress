package extensions.newsletter;

import hx.press.Pagination;
import hx.press.plugins.PluginHost;
import hx.well.facades.Inertia;
import hx.well.handler.AbstractHandler;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.ResponseBuilder;

class ListSubscribersHandler extends AbstractHandler {
    var host:PluginHost;

    public function new(host:PluginHost) {
        super();
        this.host = host;
    }

    public function execute(request:Request):AbstractResponse {
        if (!host.can("subscribers")) {
            return ResponseBuilder.asString("Access restricted.", 403);
        }
        var cursor = Pagination.cursor(request);
        var page = SubscriberData.page(cursor);
        var total = SubscriberData.count();
        var rows = page.items.map(subscriber -> {
            return {
                id: subscriber.id,
                email: subscriber.email,
                joined: Std.string(subscriber.created_at)
            };
        });
        var links = Pagination.links("/admin/subscribers", new Map(), page, cursor, total,
            subscriber -> subscriber.id, subscriber -> null);
        var pluginPage = {
            namespace: "plugin-newsletter",
            title: "Subscribers",
            description: "",
            total: total,
            columns: [
                {
                    key: "email",
                    label: "Email address"
                },
                {key: "joined", label: "Subscribed at"}
            ],
            rows: rows,
            actions: [{label: "Export CSV", href: "/admin/subscribers/export", download: true}],
            rowAction: {
                label: "Remove subscriber",
                path: "/admin/subscribers/{id}/delete",
                confirm: "Remove this subscriber?"
            },
            pagination: links,
            noun: "subscribers"
        };
        var props = {pluginPage: pluginPage};
        return Inertia.render("Admin/PluginPage", props);
    }
}
