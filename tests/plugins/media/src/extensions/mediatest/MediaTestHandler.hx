package extensions.mediatest;

import hx.press.media.MediaDependencies;
import hx.press.media.MediaLocks;
import hx.press.plugins.PluginDatabase;
import hx.press.plugins.PluginHost;
import hx.well.handler.AbstractHandler;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.ResponseBuilder;

class MediaTestHandler extends AbstractHandler {
    var host:PluginHost;

    public function new(host:PluginHost) {
        super();
        this.host = host;
    }

    public function execute(request:Request):AbstractResponse {
        if (!host.can("media")) {
            return ResponseBuilder.asJson({error: "Access restricted."}, 403);
        }
        var key:String = request.input("key", "attachment");
        if (!~/^[a-z0-9-]{1,64}$/.match(key)) {
            return ResponseBuilder.asJson({error: "Invalid attachment key."}, 422);
        }
        var dependencies = MediaDependencies.forPlugin("media-test");
        var database = new PluginDatabase("media-test");
        var action:String = request.input("action", "attach");
        switch (action) {
            case "json":
                var url:String = request.input("url", "");
                database.put(key, {gallery: {images: [{source: url}]}}, "gallery");
            case "detach":
                MediaLocks.run(() -> {
                    MediaAttachment.query.where("key", key).delete();
                    dependencies.forget('attachment:${key}');
                    database.forget(key, "gallery");
                    return true;
                });
            default:
                var id = Std.parseInt(request.input("media_id", "0")) ?? 0;
                if (action == "watch-only") {
                    MediaLocks.run(() -> {
                        MediaAttachment.query.updateOrCreate(["key" => key], ["media_id" => id]);
                        return true;
                    });
                } else {
                    dependencies.withReferences('attachment:${key}', [id], () -> {
                        MediaAttachment.query.updateOrCreate(["key" => key], ["media_id" => id]);
                        return true;
                    });
                }
        }
        return ResponseBuilder.asJson({saved: true});
    }
}
