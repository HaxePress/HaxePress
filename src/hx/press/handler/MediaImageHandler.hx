package hx.press.handler;

import hx.press.media.MediaReferences;
import hx.well.facades.Storage;
import hx.well.handler.PublicHandler;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.ResponseStatic.abort;
import hx.well.storage.InvalidStoragePath;

/** Serves media library images; anything else gets the site's own error page. **/
class MediaImageHandler extends PublicHandler {
    public override function execute(request:Request):AbstractResponse {
        var filename = request.route("filename");
        if (!MediaReferences.validFilename(filename)) {
            abort(404);
        }
        var disk = Storage.disk("media");
        try {
            if (!disk.fileExists(filename)) {
                abort(404);
            }
            return disk.response(filename, filename,
                ["Cache-Control" => "public, max-age=31536000, immutable"]);
        } catch (_:InvalidStoragePath) {
            abort(403);
            return null;
        }
    }
}
