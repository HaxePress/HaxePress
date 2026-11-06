package hx.press.handler.admin.packages;

import hx.press.CmsAccess;
import hx.press.media.ImageUploads;
import hx.press.model.Admin;
import hx.press.model.ThemeDesign;
import hx.press.themes.ThemeAiAccess;
import hx.press.themes.ThemeAiAccess.ThemeAiActor;
import hx.press.themes.ThemeAssets;
import hx.well.handler.AbstractHandler;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.RequestStatic.auth;
import hx.well.http.ResponseBuilder;

class UploadThemeImageHandler extends AbstractHandler {
    final ai:Bool;
    final verification:Bool;

    public function new(ai:Bool = false, verification:Bool = false) {
        super();
        this.ai = ai;
        this.verification = verification;
    }

    public function execute(request:Request):AbstractResponse {
        var actor:ThemeAiActor = request.getAttribute(ThemeAiAccess.ACTOR);
        var permitted = ai ? actor != null && actor.permissions.edit : CmsAccess.can("extensions");
        if (!permitted) {
            return ResponseBuilder.asJson({error: "Your account cannot upload theme images."}, 403);
        }
        var themeId = request.route("id");
        if (!ThemeAssets.validThemeId(themeId) || !ThemeDesign.query.where("id", themeId)
            .exists()) {
            return ResponseBuilder.asJson({error: "This theme is no longer available."}, 404);
        }
        var userId = ai ? actor.id : (cast auth("admin").user() : Admin).id;
        var credential = ai ? actor.uploadKey : 'admin:${request.session.sessionKey}';
        try {
            return verification ? ImageUploads.verify(request, userId, credential,
                themeId) : ImageUploads.stage(request, userId, credential, themeId, 422);
        } catch (error:Dynamic) {
            return ResponseBuilder.asJson({error: Std.string(error)}, 422);
        }
    }
}
