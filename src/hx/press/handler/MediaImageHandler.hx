package hx.press.handler;

import hx.press.media.MediaReferences;
import hx.well.handler.PublicHandler;
import hx.well.http.Request;
import hx.well.http.AbstractResponse;
import hx.well.http.ResponseBuilder;
import hx.well.facades.Storage;
import hx.well.storage.InvalidStoragePath;

class MediaImageHandler extends PublicHandler {
    public override function execute(request:Request):AbstractResponse {
        var filename = request.route("filename");
        if (!MediaReferences.validFilename(filename))
            return ResponseBuilder.asString("Image not found.", 404)
                .header("Content-Type", "text/plain; charset=utf-8");
        var disk = Storage.disk("media");
        try {
            if (!disk.fileExists(filename)) {
                return ResponseBuilder.asString("Image not found.", 404);
            }
            return disk.response(filename, filename,
                ["Cache-Control" => "public, max-age=31536000, immutable"]);
        } catch (_:InvalidStoragePath) {
            return ResponseBuilder.asString("Image not found.", 403);
        }
    }
}
