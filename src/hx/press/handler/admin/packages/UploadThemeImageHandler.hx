package hx.press.handler.admin.packages;

import hx.press.CmsAccess;
import hx.press.media.MediaReferences;
import hx.press.themes.ThemeAiAccess;
import hx.press.themes.ThemeAiAccess.ThemeAiActor;
import hx.press.themes.ThemeAssets;
import hx.well.handler.AbstractHandler;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.ResponseBuilder;

class UploadThemeImageHandler extends AbstractHandler {
    final ai:Bool;

    public function new(ai:Bool = false) {
        super();
        this.ai = ai;
    }

    public function execute(request:Request):AbstractResponse {
        var actor:ThemeAiActor = request.getAttribute(ThemeAiAccess.ACTOR);
        var permitted = ai ? actor != null && actor.permissions.edit : CmsAccess.can("extensions");
        if (!permitted) {
            return ResponseBuilder.asJson({error: "Your account cannot upload theme images."}, 403);
        }
        var bytes = request.bodyBytes;
        if (bytes == null || bytes.length == 0) {
            return ResponseBuilder.asJson({error: "Choose an image to upload."}, 422);
        }
        if (bytes.length > MediaReferences.MAX_BYTES) {
            return ResponseBuilder.asJson({error: "Choose an image smaller than 5 MB."}, 413);
        }
        var label = request.header("X-File-Name", "");
        try {
            label = StringTools.urlDecode(label).substr(0, 180);
        } catch (_:Dynamic) {
            label = "";
        }
        try {
            var asset = ThemeAssets.upload(request.route("id"), bytes, label);
            return ResponseBuilder.asJson(asset, 201);
        } catch (error:Dynamic) {
            return ResponseBuilder.asJson({error: Std.string(error)}, 422);
        }
    }
}
