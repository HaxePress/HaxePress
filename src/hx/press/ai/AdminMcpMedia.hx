package hx.press.ai;

import hx.press.CmsAccess;
import hx.press.media.MediaReferences;
import hx.press.model.MediaAsset;
import hx.well.facades.Storage;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.ResponseBuilder;

class AdminMcpMedia {
    public static function image(request:Request):AbstractResponse {
        if (!request.getAttribute(AdminMcpAccess.INTERNAL, false) || !CmsAccess.can("media")) {
            return ResponseBuilder.asJson({error: "This account cannot browse the media library."},
                403);
        }
        return read(Std.parseInt(request.route("id")));
    }

    public static function read(id:Int):AbstractResponse {
        var image = MediaAsset.query.select(["filename", "mime_type"])
            .where("id", id)
            .limit(1)
            .first();
        var disk = Storage.disk("media");
        if (image == null
            || !MediaReferences.validFilename(image.filename)
            || !MediaReferences.mimeTypes.contains(image.mime_type)
            || !disk.fileExists(image.filename)
            || disk.size(image.filename) > MediaReferences.MAX_BYTES) {
            return
                ResponseBuilder.asJson({error: "Choose an available image from the media library."},
                    404);
        }
        return disk.response(image.filename, image.filename,
            ["Content-Type" => image.mime_type, "Cache-Control" => "private, no-store"]);
    }

    public static function info(request:Request):AbstractResponse {
        if (!request.getAttribute(AdminMcpAccess.INTERNAL, false) || !CmsAccess.can("media")) {
            return ResponseBuilder.asJson({error: "This account cannot browse the media library."},
                403);
        }
        var image = MediaAsset.query.select(["id", "filename", "alt"])
            .where("id", Std.parseInt(request.route("id")))
            .limit(1)
            .first();
        var disk = Storage.disk("media");
        if (image == null || !MediaReferences.validFilename(image.filename)
            || !disk.fileExists(image.filename)) {
            return
                ResponseBuilder.asJson({error: "Choose an available image from the media library."},
                    404);
        }
        return ResponseBuilder.asJson({id: image.id, url: disk.url(image.filename), alt: image.alt})
            .header("Cache-Control", "private, no-store");
    }
}
