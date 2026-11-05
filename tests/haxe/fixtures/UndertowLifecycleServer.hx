package fixtures;

import hx.well.HxWell;
import hx.well.facades.Environment;
import hx.well.http.ResponseBuilder;
import haxe.Json;
import hx.well.http.driver.undertow.UndertowExtern;
import hx.well.http.driver.undertow.UndertowExtern.HttpHandlerExtern;
import hx.well.http.driver.undertow.UndertowExtern.HttpServerExchangeExtern;
import hx.well.http.driver.undertow.UndertowWebSocketExtern.WebSocketProtocolHandshakeHandlerExtern;
import hx.well.http.driver.undertow.UndertowWebSocketHandler.UndertowWebSocketCallback;
import hx.well.route.Route;

using hx.well.tools.RouteElementTools;

class UndertowLifecycleServer {
    public static function main():Void {
        HxWell.middlewares = [];
        var probe = new WebSocketLifecycleProbe();
        Route.websocket("/__fixtures/ws/lifecycle").handler(probe);
        Route.get("/__fixtures/ws/status", request -> ResponseBuilder.asJson(probe.status()));
        Route.post("/__fixtures/ws/release", request -> {
            probe.release();
            return ResponseBuilder.asJson({released: true});
        });
        var port = Std.parseInt(Environment.env("PORT", "1337"));
        var root = new WebSocketProtocolHandshakeHandlerExtern(new UndertowWebSocketCallback(),
            new LifecycleStatusHandler(probe));
        var server = UndertowExtern.builder()
            .addHttpListener(port, "127.0.0.1")
            .setHandler(root)
            .build();
        server.start();
    }
}

private class LifecycleStatusHandler implements HttpHandlerExtern {
    final probe:WebSocketLifecycleProbe;

    public function new(probe:WebSocketLifecycleProbe) {
        this.probe = probe;
    }

    public function handleRequest(exchange:HttpServerExchangeExtern):Void {
        if (exchange.getRequestPath() == "/__fixtures/ws/release") {
            probe.release();
        }
        exchange.setStatusCode(200);
        exchange.getResponseSender().send(Json.stringify(probe.status()));
    }
}
