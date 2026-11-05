package extensions.newsletter;

import hx.well.handler.AbstractHandler;
import hx.press.plugins.PluginHost;
import hx.well.facades.Environment;
import hx.well.http.Request;
import hx.well.http.AbstractResponse;
import hx.well.http.ResponseBuilder;
import hx.press.ContentCache;

class DeleteSubscriberHandler extends AbstractHandler {
    var host:PluginHost;

    public function new(host:PluginHost) {
        super();
        this.host = host;
    }

    public function execute(request:Request):AbstractResponse {
        if (!host.can("subscribers")) {
            return ResponseBuilder.asString("Access restricted.", 403);
        }
        var subscriber = Subscriber.query.select(["id"])
            .where("id", Std.parseInt(request.route("id")))
            .limit(1)
            .first();
        if (subscriber != null) {
            subscriber.delete();
            ContentCache.changed("subscribers");
        }
        return ResponseBuilder.asRedirect("/admin/subscribers", 303);
    }
}
