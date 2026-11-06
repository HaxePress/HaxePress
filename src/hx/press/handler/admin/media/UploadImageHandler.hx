package hx.press.handler.admin.media;

import hx.press.media.ImageUploads;
import hx.press.model.Admin;
import hx.well.handler.AbstractHandler;
import hx.well.http.Request;
import hx.well.http.RequestStatic.auth;
import hx.well.http.AbstractResponse;
import hx.well.http.ResponseBuilder;
import hx.press.CmsAccess;

class UploadImageHandler extends AbstractHandler {
    final verification:Bool;

    public function new(verification:Bool = false) {
        super();
        this.verification = verification;
    }

    public function execute(request:Request):AbstractResponse {
        if (!CmsAccess.can("media")) {
            return ResponseBuilder.asJson({error: "Your account cannot upload images."}, 403);
        }
        var admin:Admin = auth("admin").user();
        var credential = 'admin:${request.session.sessionKey}';
        try {
            return verification ? ImageUploads.verify(request, admin.id, credential,
                "") : ImageUploads.stage(request, admin.id, credential, "");
        } catch (error:Dynamic) {
            trace('Image upload failed: ${Std.string(error)}');
            return
                ResponseBuilder.asJson({error: "The image could not be saved. Please try again."},
                    500);
        }
    }
}
