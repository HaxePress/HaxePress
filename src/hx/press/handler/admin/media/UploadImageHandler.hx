package hx.press.handler.admin.media;

import hx.press.media.MediaReferences;
import hx.well.handler.AbstractHandler;
import hx.well.http.Request;
import hx.well.http.AbstractResponse;
import hx.well.http.ResponseBuilder;
import hx.press.MediaStorage;
import hx.press.CmsAccess;

class UploadImageHandler extends AbstractHandler {
    public function execute(request:Request):AbstractResponse {
        if (!CmsAccess.can("media")) {
            return ResponseBuilder.asJson({error: "Your account cannot upload images."}, 403);
        }
        var bytes = request.bodyBytes;
        if (bytes == null || bytes.length == 0)
            return ResponseBuilder.asJson({error: "Choose an image to upload."}, 422);
        if (bytes.length > MediaReferences.MAX_BYTES)
            return ResponseBuilder.asJson({error: "Choose an image smaller than 5 MB."}, 413);
        var format = MediaStorage.format(bytes);
        if (format == null)
            return ResponseBuilder.asJson({error: "Choose a JPEG, PNG, WebP or GIF image."}, 415);
        var dimensions = MediaStorage.dimensions(bytes);
        if (dimensions == null)
            return
                ResponseBuilder.asJson({error: "This image could not be read. Use a valid image under 20 megapixels."},
                422);
        try {
            var label = request.header("X-File-Name") ?? "";
            try {
                label = StringTools.urlDecode(label).substr(0, 180);
            } catch (invalid:Dynamic) {
                label = "";
            }
            return ResponseBuilder.asJson(MediaStorage.save(bytes, format, dimensions, label), 201);
        } catch (error:Dynamic) {
            trace("Image upload failed: " + Std.string(error));
            return
                ResponseBuilder.asJson({error: "The image could not be saved. Please try again."},
                    500);
        }
    }
}
