package hx.press.config;

import hx.well.config.IConfig;
import hx.well.server.instance.IInstance;
import hx.press.ServerSettings;
#if (!cms_plugin && php)
import hx.well.http.driver.php.PHPInstance;
#elseif !cms_plugin
import hx.press.http.BodyLimits;
import hx.press.mcp.McpEndpoint;
import hx.well.http.driver.crossbyte.CrossbyteInstance;
#end

class InstanceConfig implements IConfig {
    public function new() {}

    public function get():Array<IInstance> {
        #if cms_plugin
        return [];
        #elseif php
        // The web server runs index.php for each request; HxWell's PHP driver handles it.
        return [PHPInstance.builder().build()];
        #else
        return [
            CrossbyteInstance.builder()
                .setHost(ServerSettings.host)
                .setPort(ServerSettings.port)
                .setMaxConnections(ServerSettings.connections)
                .setMaxConcurrentRequests(ServerSettings.connections)
                .setPoolSize(ServerSettings.workers)
                .setWebSocketLimits(McpEndpoint.MAX_REQUEST_BYTES, McpEndpoint.MAX_RESPONSE_BYTES,
                    McpEndpoint.MAX_RESPONSE_BYTES)
                .configureHttp(http -> {
                    http.http2Enabled = true;
                    http.requestTimeout = 30;
                    http.compression.enabled = true;
                    http.rateLimiter = null;
                    http.maxRequestBodySizeFor = BodyLimits.limit;
                })
                .build()];
        #end
    }
}
