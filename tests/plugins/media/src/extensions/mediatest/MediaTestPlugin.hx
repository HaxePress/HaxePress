package extensions.mediatest;

import hx.press.media.MediaDependencies;
import hx.press.media.MediaDependencyMode;
import hx.press.plugins.PluginDatabase;
import hx.press.plugins.PluginEntrypoint;
import hx.press.plugins.PluginHost;
import hx.press.plugins.PluginMigration;
import hx.well.route.Route;
import hx.well.route.RouteElement;

class MediaTestPlugin implements PluginEntrypoint {
    var route:RouteElement;

    public function new() {}

    public function onCreate(host:PluginHost, context:String):Void {
        var database = new PluginDatabase("media-test");
        var schema = database.schema();
        database.migrate([
            new PluginMigration("001_attachments", () -> {
                if (!schema.hasTable(database.tableName("attachments"))) {
                    schema.create(database.tableName("attachments"), table -> {
                        table.id();
                        table.string("key").unique();
                        table.integer("media_id");
                        table.index(["media_id"]);
                    });
                }
            })
        ]);
        MediaDependencies.forPlugin("media-test")
            .watch("attachments", new MediaAttachment(), "media_id", MediaDependencyMode.Id);
        host.admin(() -> route = Route.post("/media-test", new MediaTestHandler(host)));
    }

    public function onDestroy():Void {
        Route.unregister(route);
    }

    public function dispatch(event:String, context:String):String {
        return "{}";
    }
}
