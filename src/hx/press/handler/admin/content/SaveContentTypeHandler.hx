package hx.press.handler.admin.content;

import hx.well.handler.AbstractHandler;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.RequestStatic.request;
import hx.well.http.ResponseBuilder;
import hx.well.validator.ValidatorRule;
import hx.press.validation.ValidationResponder;
import hx.press.CmsAccess;
import hx.press.CmsController;
import hx.press.Activity;
import haxe.Json;
import hx.press.content.ContentTypes;
import hx.press.content.ContentTypeController;

class SaveContentTypeHandler extends AbstractHandler implements ValidationResponder {
    public override function validate():Bool {
        if (!CmsAccess.can("settings")) {
            return true;
        }
        return request().validate(["definition" => [Required, String, Min(1), Max(60000)]]);
    }

    public function validationFailed(request:Request):AbstractResponse {
        var creating = request.route("key") == null;
        return ContentTypeController.editor(request, creating,
            "The collection definition exceeds its size limit.", 422);
    }

    public function execute(request:Request):AbstractResponse {
        if (!CmsAccess.can("settings")) {
            return CmsController.forbidden(request);
        }
        var routeKey = request.route("key");
        var creating = routeKey == null;
        try {
            var values = request.only("definition");
            var source:String = values.get("definition");
            var input:Dynamic = Json.parse(source);
            if (!creating && (routeKey == null || routeKey != input.key)) {
                throw "Content type keys cannot be changed after creation.";
            }
            var existing = creating ? null : ContentTypes.find(routeKey, false);
            var owner = existing == null ? "" : existing.owner;
            var key = ContentTypes.save(input, owner, creating);
            Activity.record("saved", "content_type", 0, key);
            return ResponseBuilder.asRedirect('/admin/content-types/${key}/edit?notice=saved', 303);
        } catch (error:Dynamic) {
            return ContentTypeController.editor(request, creating, Std.string(error), 422);
        }
    }
}
