package extensions.newsletter;

import hx.press.plugins.PluginHost;
import hx.well.facades.Storage;
import hx.well.handler.AbstractHandler;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.ResponseBuilder;
import hx.well.internal.SecureToken;

class ExportSubscribersHandler extends AbstractHandler {
    var host:PluginHost;

    public function new(host:PluginHost) {
        super();
        this.host = host;
    }

    public function execute(request:Request):AbstractResponse {
        if (!host.can("subscribers")) {
            return ResponseBuilder.asString("Access restricted.", 403);
        }
        var disk = Storage.disk("exports");
        var path = SecureToken.generate(32) + ".csv";
        var source = new CsvExportInput();
        try {
            disk.writeStream(path, source);
            source.close();
            var response = disk.download(path, "subscribers.csv",
                ["Content-Type" => "text/csv; charset=utf-8"]);
            response.input = new ExportInput(response.input, () -> {
                disk.delete(path);
            });
            return response;
        } catch (error:Dynamic) {
            source.close();
            if (disk.fileExists(path)) {
                disk.delete(path);
            }
            throw error;
        }
    }
}
