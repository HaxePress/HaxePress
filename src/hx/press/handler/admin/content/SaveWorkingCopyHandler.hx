package hx.press.handler.admin.content;

import hx.press.content.ContentLocks;
import haxe.Json;
import hx.press.AdminController;
import hx.press.CmsAccess;
import hx.press.ContentController;
import hx.press.SiteController;
import hx.press.TagData;
import hx.press.WorkingCopies;
import hx.press.content.ContentFields;
import hx.press.content.ContentTypes;
import hx.press.model.ContentItem;
import hx.press.validation.ValidationResponder;
import hx.well.handler.AbstractHandler;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.RequestStatic.request;
import hx.well.http.ResponseBuilder;
import hx.well.validator.ValidatorRule;
import hx.well.tools.MapTools;

class SaveWorkingCopyHandler extends AbstractHandler implements ValidationResponder {
    final resolve:Request->String;

    public function new(resolve:Request->String) {
        super();
        this.resolve = resolve;
    }

    public override function validate():Bool {
        var current = request();
        var kind = resolve(current);
        if (ContentTypes.find(kind) == null || !CmsAccess.canCollection(kind)) {
            return true;
        }
        var rawId = AdminController.input(current, "id", 16);
        if (rawId != "" && !~/^[0-9]+$/.match(rawId)) {
            return true;
        }
        var id = Std.parseInt(rawId) ?? 0;
        if (id > 0) {
            var item = ContentItem.query.select(["author_id", "content_type", "version"])
                .where("id", id)
                .first();
            var expected = Std.parseInt(AdminController.input(current, "version", 16)) ?? 1;
            if (item == null
                || item.content_type != kind
                || !CmsAccess.canEdit(item.author_id)
                || item.version != expected) {
                return true;
            }
        }
        return current.validate([
            "title" => [String, Max(180)],
            "content" => [String, Max(100000)],
            "excerpt" => [String, Max(500)],
            "tags" => [String, Max(1000)],
            "slug" => [String, Max(180)],
            "category" => [String, Max(80)],
            "image" => [String, Max(300)],
            "image_alt" => [String, Max(300)],
            "status" => [String, Max(20)],
            "featured" => [String, Max(1)],
            "published_at" => [String, Max(40)],
            "seo_title" => [String, Max(180)],
            "seo_description" => [String, Max(500)],
            "scheduled_epoch" => [String, Max(30)],
            "custom_fields" => [String, Max(64000)]
        ]);
    }

    public function validationFailed(request:Request):AbstractResponse {
        return ResponseBuilder.asJson({error: "The working copy exceeds the editor limits."}, 422);
    }

    public function execute(request:Request):AbstractResponse {
        var kind = resolve(request);
        if (ContentTypes.find(kind) == null) {
            return SiteController.notFound(request);
        }
        if (!CmsAccess.canCollection(kind)) {
            return ResponseBuilder.asJson({error: "Your account cannot save working copies."}, 403);
        }
        var idInput = AdminController.input(request, "id", 16);
        if (idInput != "" && !~/^[0-9]+$/.match(idInput)) {
            return ResponseBuilder.asJson({error: "Invalid content identifier."}, 422);
        }
        var id = Std.parseInt(idInput) ?? 0;
        var lockKey = id > 0 ? "document-" + id : "new-" + CmsAccess.current().id + "-" + kind;
        return ContentLocks.run("type-" + kind,
            () -> ContentLocks.run(lockKey, () -> saveWorkingLocked(request, kind)));
    }

    static function saveWorkingLocked(request:Request, kind:String):AbstractResponse {
        if (ContentTypes.find(kind) == null) {
            return SiteController.notFound(request);
        }
        var id = Std.parseInt(AdminController.input(request, "id", 16)) ?? 0;
        if (!CmsAccess.canCollection(kind) || (id > 0 && !ContentController.owned(id, kind))) {
            return
                ResponseBuilder.asJson({error: "This working copy cannot be saved by your account."},
                    403);
        }
        var baseVersion = Std.parseInt(AdminController.input(request, "version", 16)) ?? 1;
        if (id > 0) {
            var current = ContentItem.query.select(["version"]).where("id", id).limit(1).first();
            if (current == null || current.version != baseVersion) {
                return
                    ResponseBuilder.asJson({error: "The saved version changed. Reload it before continuing."},
                        409);
            }
        }

        var values = request.only("title", "slug", "excerpt", "content", "category", "image",
            "image_alt", "status", "featured", "published_at", "tags", "seo_title",
            "seo_description", "scheduled_epoch");
        for (field in values.keys()) {
            values.set(field, request.input(field));
        }
        var payload = MapTools.toDynamic(values);
        var tagInput:Dynamic = request.input("tags", "");
        payload.tagRecords = TagData.parse(tagInput) ?? [];
        var admin = CmsAccess.current();
        try {
            var previous = id == 0 ? {} : ContentFields.values(id, ContentTypes.find(kind));
            var customFields = ContentFields.decode(request.input("custom_fields", null), previous);
            payload.custom_fields = Json.stringify(customFields);
            var key = WorkingCopies.save(admin.id, kind, id,
                AdminController.input(request, "draft_key", 128),
                Std.parseInt(AdminController.input(request, "draft_version", 16)) ?? 1,
                baseVersion, payload);
            return ResponseBuilder.asJson({saved: true, key: key});
        } catch (error:Dynamic) {
            return ResponseBuilder.asJson({error: Std.string(error)}, 422);
        }
    }
}
