package hx.press.handler.admin.tag;

import hx.press.Activity;
import hx.press.AdminController;
import hx.press.CategoryData;
import hx.press.CmsAccess;
import hx.press.CmsController;
import hx.press.ContentCache;
import hx.press.SiteController;
import hx.press.SiteSettingsStore;
import hx.press.model.Tag;
import hx.press.validation.PositiveInt;
import hx.press.validation.Slug;
import hx.press.validation.ValidationResponder;
import hx.well.handler.AbstractHandler;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.RequestStatic.request;
import hx.well.http.ResponseBuilder;
import hx.well.validator.ValidatorRule;

using StringTools;

class SaveTagHandler extends AbstractHandler implements ValidationResponder {
    public override function validate():Bool {
        var current = request();
        if (!CmsAccess.can("taxonomy")) {
            return true;
        }
        var rawId = AdminController.input(current, "id", 16);
        if (rawId != ""
            && (PositiveInt.parse(rawId) == null || !Tag.query.where("id", rawId).exists())) {
            return true;
        }
        return current.validate([
            "name" => [Required, String, Min(1), Max(80)],
            "slug" => [Required, String, Min(1), Max(120)],
            "description" => [String, Max(500)]
        ]);
    }

    public function validationFailed(request:Request):AbstractResponse {
        return CmsController.tags(request,
            "Enter a name and a URL slug using lowercase letters, numbers and hyphens.", 422);
    }

    public function execute(request:Request):AbstractResponse {
        if (!CmsAccess.can("taxonomy")) {
            return CmsController.forbidden(request);
        }
        var rawId = AdminController.input(request, "id", 16);
        if (rawId != "" && PositiveInt.parse(rawId) == null) {
            return SiteController.notFound(request);
        }
        var existing = rawId == "" ? null : Tag.query.select(["id"])
            .where("id", rawId)
            .limit(1)
            .first();
        if (rawId != "" && existing == null) {
            return SiteController.notFound(request);
        }
        var id = existing == null ? 0 : existing.id;

        var name = CategoryData.normalize(AdminController.input(request, "name", 80));
        var slug = CategoryData.key(AdminController.input(request, "slug", 120));
        var description = AdminController.input(request, "description", 500);
        if (name == "" || !Slug.valid(slug)) {
            return CmsController.tags(request,
                "Enter a name and a URL slug using lowercase letters, numbers and hyphens.", 422);
        }
        var nameKey = CategoryData.key(name);
        var duplicateName = Tag.query.where("name_key", nameKey).where("id", "!=", id).exists();
        var duplicateSlug = Tag.query.where("slug", slug).where("id", "!=", id).exists();
        if (duplicateName || duplicateSlug) {
            return CmsController.tags(request, "A tag with this name or URL slug already exists.",
                422);
        }
        var values:Map<String, Dynamic> = [
            "name" => name,
            "name_key" => nameKey,
            "slug" => slug,
            "description" => description,
            "updated_at" => SiteSettingsStore.timestamp()
        ];
        if (existing == null) {
            values.set("created_at", SiteSettingsStore.timestamp());
            var createdId = Tag.query.insert(values);
            Activity.record("created", "tag", createdId, name);
        } else {
            existing.update(values);
            Activity.record("updated", "tag", existing.id, name);
        }
        ContentCache.changed("tags");
        return ResponseBuilder.asRedirect("/admin/tags?notice=saved", 303);
    }
}
