package hx.press.config;

import hx.well.config.IConfig;
import hx.well.server.instance.IInstance;
import hx.press.ServerSettings;
import hx.press.themes.ThemeMcpHost;
#if !cms_plugin
import hx.press.http.BodyLimits;
import hx.well.http.driver.crossbyte.CrossbyteInstance;
#end

class InstanceConfig implements IConfig {
    public function new() {}

    public function get():Array<IInstance> {
        #if cms_plugin
        return [];
        #else
        return [
            CrossbyteInstance.builder()
                .setHost(ServerSettings.host)
                .setPort(ServerSettings.port)
                .setMaxConnections(ServerSettings.connections)
                .setMaxConcurrentRequests(ServerSettings.connections)
                .setPoolSize(ServerSettings.workers)
                .setWebSocketLimits(ThemeMcpHost.MAX_REQUEST_BYTES,
                    ThemeMcpHost.MAX_RESPONSE_BYTES, ThemeMcpHost.MAX_RESPONSE_BYTES)
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
