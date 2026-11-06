package fixtures;

import hx.well.database.Connection;
import hx.well.facades.Environment;
import hx.well.provider.AbstractProvider;
import sys.db.Sqlite;
import hx.well.route.Route;
import hx.well.http.ResponseBuilder;

using hx.well.tools.RouteElementTools;

class TestProvider extends AbstractProvider {
    public function boot():Void {
        if (Environment.env("DB_DRIVER", "sqlite") == "sqlite") {
            var path = Environment.env("DB_PATH");
            Connection.create("default", {path: path},
                () -> new GuardedConnection(Sqlite.open(path)));
        }
        var probe = new WebSocketLifecycleProbe();
        Route.websocket("/__fixtures/ws/lifecycle").handler(probe);
        Route.get("/__fixtures/ws/status", request -> ResponseBuilder.asJson(probe.status()));
        Route.post("/__fixtures/ws/release", request -> {
            probe.release();
            return ResponseBuilder.asJson({released: true});
        });
    }
}
