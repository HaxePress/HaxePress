package hx.press.handler.admin.media;

import hx.press.AdminController;
import hx.press.CmsAccess;
import hx.press.CmsController;
import hx.press.ContentCache;
import hx.press.MediaController;
import hx.press.SiteSettingsStore;
import hx.press.model.MediaAsset;
import hx.press.validation.PositiveInt;
import hx.press.validation.ValidationResponder;
import hx.well.handler.AbstractHandler;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.RequestStatic.request;
import hx.well.http.ResponseBuilder;
import hx.well.validator.ValidatorRule;

class SaveMediaHandler extends AbstractHandler implements ValidationResponder {
    public override function validate():Bool {
        var current = request();
        if (!CmsAccess.can("media")) {
            return true;
        }
        return current.validate(["title" => [String, Max(180)], "alt" => [String, Max(500)]]);
    }

    public function validationFailed(request:Request):AbstractResponse {
        var id = PositiveInt.route(request, "id");
        return MediaController.index(request,
            "Use at most 180 characters for the title and 500 for the image description.", 422,
            '/admin/media?edit=${id}');
    }

    public function execute(request:Request):AbstractResponse {
        if (!CmsAccess.can("media")) {
            return CmsController.forbidden(request);
        }

        var id = PositiveInt.route(request, "id");
        MediaAsset.query.where("id", id).update([
            "title" => AdminController.input(request, "title", 180),
            "alt" => AdminController.input(request, "alt", 500),
            "updated_at" => SiteSettingsStore.timestamp()
        ]);
        ContentCache.changed("media");
        return ResponseBuilder.asRedirect("/admin/media?notice=saved", 303);
    }
}
