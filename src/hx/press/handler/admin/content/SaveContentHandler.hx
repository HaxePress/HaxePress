package hx.press.handler.admin.content;

import hx.press.media.MediaReferences;
import hx.press.media.MediaLocks;
import hx.press.content.ContentLocks;
import hx.press.AdminController;
import hx.press.SiteController;
import hx.press.ContentCache;
import hx.press.MediaStorage;
import hx.press.ContentItemData;
import hx.press.SiteSettingsStore;
import hx.press.Activity;
import hx.press.CmsAccess;
import hx.press.CmsController;
import hx.press.ContentController;
import hx.press.ContentHistory;
import hx.press.TagData;
import hx.press.WorkingCopies;
import haxe.Exception;
import hx.press.plugins.PluginRuntime;
import hx.well.facades.DBStatic;
import hx.well.handler.AbstractHandler;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.ResponseBuilder;
import hx.press.model.Category;
import hx.press.model.ContentItem;
import hx.well.validator.ValidatorRule;
import hx.well.http.RequestStatic.request;
import hx.press.validation.ValidationResponder;
import hx.press.content.ContentTypes;
import hx.press.content.ContentTypeDefinition;
import hx.press.content.ContentFields;
import hx.press.i18n.I18n;

using StringTools;

class SaveContentHandler extends AbstractHandler implements ValidationResponder {
    final resolve:Request->String;

    public function new(resolve:Request->String) {
        super();
        this.resolve = resolve;
    }

    public override function validate():Bool {
        var current = request();
        var kind = resolve(current);
        var type = ContentTypes.find(kind);
        if (type == null || !CmsAccess.can(type.capability)) {
            return true;
        }
        var rawId = AdminController.input(current, "id", 16);
        if (rawId != "" && !~/^[1-9][0-9]*$/.match(rawId)) {
            return true;
        }
        var id = Std.parseInt(rawId) ?? 0;
        var expected = AdminController.input(current, "version", 16);
        if (expected != "" && !~/^[1-9][0-9]*$/.match(expected)) {
            return true;
        }
        var version = Std.parseInt(expected);
        if (id > 0
            && ((expected != "" && version == null) || !ContentController.owned(id, kind,
                version))) {
            return true;
        }
        return current.validate([
            "title" => [Required, String, Min(type.minimumTitleLength), Max(180)],
            "slug" => [Required, String, Min(1), Max(180)],
            "excerpt" => [String, Max(500)],
            "content" => [String, Max(100000)],
            "category" => [String, Max(80)],
            "image" => [String, Max(2000)],
            "image_alt" => [String, Max(500)],
            "status" => [Required, String, Regex("^(draft|published|scheduled)$")],
            "published_at" => [String, Max(50)],
            "seo_title" => [String, Max(180)],
            "seo_description" => [String, Max(500)],
            "tags" => [String, Max(1000)],
            "version" => [String, Max(16)]
        ]);
    }

    public function validationFailed(request:Request):AbstractResponse {
        var kind = resolve(request);
        var type = ContentTypes.find(kind);
        if (type == null) {
            return SiteController.notFound(request);
        }
        if (!CmsAccess.can(type.capability)) {
            return CmsController.forbidden(request);
        }
        var id = Std.parseInt(AdminController.input(request, "id", 16)) ?? 0;
        var existing = id == 0 ? null : ContentItem.query.where("id", id)
            .where("content_type", kind)
            .first();
        if (id > 0 && existing == null) {
            return SiteController.notFound(request);
        }
        if (existing != null && !CmsAccess.canEdit(existing.author_id)) {
            return CmsController.forbidden(request);
        }
        var form = readForm(request, type, id, existing);
        return ContentController.editor(request, form.toObject(),
            "Check the content fields and their length limits before saving.", 422);
    }

    function readForm(request:Request, type:ContentTypeDefinition, id:Int,
            existing:ContentItem):ContentItem {
        var admin = CmsAccess.current();
        var form = new ContentItem();
        form.id = id;
        form.content_type = type.key;
        form.author_id = existing == null ? admin.id : existing.author_id;
        form.version = existing == null ? 1 : existing.version;
        form.title = AdminController.input(request, "title", 500);
        form.slug = AdminController.input(request, "slug", 500).toLowerCase();
        form.excerpt = AdminController.input(request, "excerpt", 2000);
        var rawContent:Dynamic = request.input("content", "");
        form.content = (rawContent is String) ? rawContent : "";
        form.category = ContentTypes.supports(type,
            "categories") ? AdminController.input(request, "category",
                100) : existing == null ? "" : existing.category;
        form.image = AdminController.input(request, "image", 2000);
        form.image_alt = AdminController.input(request, "image_alt", 500);
        form.status = AdminController.input(request, "status", 30);
        form.featured = ContentTypes.supports(type, "featured")
            && request.input("featured", "0") == "1" ? 1 : 0;
        form.published_at = AdminController.input(request, "published_at", 50);
        form.seo_title = AdminController.input(request, "seo_title", 200);
        form.seo_description = AdminController.input(request, "seo_description", 600);
        form.scheduled_epoch = Std.parseFloat(AdminController.input(request, "scheduled_epoch",
            32));
        if (!Math.isFinite(form.scheduled_epoch)) {
            form.scheduled_epoch = 0;
        }
        if (!ContentTypes.supports(type, "body")) {
            form.content = existing == null ? "" : existing.content;
        }
        if (!ContentTypes.supports(type, "excerpt")) {
            form.excerpt = existing == null ? "" : existing.excerpt;
        }
        if (!ContentTypes.supports(type, "image")) {
            form.image = existing == null ? "" : existing.image;
            form.image_alt = existing == null ? "" : existing.image_alt;
        }
        if (!ContentTypes.supports(type, "seo")) {
            form.seo_title = existing == null ? "" : existing.seo_title;
            form.seo_description = existing == null ? "" : existing.seo_description;
        }
        return form;
    }

    public function execute(request:Request):AbstractResponse {
        var kind = resolve(request);
        if (!ContentTypes.exists(kind)) {
            return SiteController.notFound(request);
        }
        if (!CmsAccess.canCollection(kind)) {
            return CmsController.forbidden(request);
        }
        var rawId = AdminController.input(request, "id", 16);
        if (rawId != "" && !~/^[1-9][0-9]*$/.match(rawId)) {
            return SiteController.notFound(request);
        }
        var id = Std.parseInt(rawId) ?? 0;
        var admin = CmsAccess.current();
        var lockKey = id == 0 ? 'new-${admin.id}-${kind}' : 'document-${id}';
        return ContentLocks.run('type-${kind}',
            () -> ContentLocks.run(lockKey, () -> save(request, id, kind)));
    }

    function save(request:Request, id:Int, kind:String):AbstractResponse {
        var type = ContentTypes.find(kind);
        if (type == null) {
            return SiteController.notFound(request);
        }
        var admin = CmsAccess.current();
        // The old body is needed for its first revision; this is a single ID lookup.
        var existing = id == 0 ? null : ContentItem.query.where("id", id)
            .where("content_type", kind)
            .limit(1)
            .first();
        if (id > 0 && existing == null) {
            return SiteController.notFound(request);
        }
        if (existing != null && !CmsAccess.canEdit(existing.author_id)) {
            return CmsController.forbidden(request);
        }
        var form = readForm(request, type, id, existing);

        var error = "";
        if (form.title.length < type.minimumTitleLength) {
            error = "Check the content fields and their length limits before saving.";
        } else if (!~/^[a-z0-9]+(-[a-z0-9]+)*$/.match(form.slug)) {
            error = "Use lowercase letters, numbers, and single hyphens for the URL slug.";
        } else if (ContentTypes.supports(type, "excerpt")
            && form.excerpt.length < type.minimumExcerptLength) {
            error = I18n.t("The excerpt must contain at least {count} characters.",
                ["count" => type.minimumExcerptLength]);
        } else if (ContentTypes.supports(type, "categories")
            && !Category.query.where("name", form.category).exists()) {
            error = "Choose an existing category. You can manage categories in the admin panel.";
        } else if (form.status != "draft" && ContentTypes.supports(type, "body")
            && form.content.length < type.minimumContentLength) {
            error = I18n.t("Add at least {count} characters before publishing or scheduling this content.",
                ["count" => type.minimumContentLength]);
        } else if (form.status != "draft" && !CmsAccess.can("publish")) {
            error = "Your account can save drafts. An editor or owner can publish them.";
        } else if (existing != null && ["published", "scheduled"].contains(existing.status)
            && !CmsAccess.can("publish")) {
            error = "An editor or owner can update published or scheduled content. Your working copy is kept separately.";
        } else if (existing != null && existing.status == "trash") {
            error = "Restore this content from the trash before editing it.";
        } else if (form.image != "" && !MediaReferences.storedImage(form.image)) {
            error = "Upload a cover image using the image uploader.";
        } else if (!MediaStorage.contentUsesStoredImages(form.content)) {
            error = "Upload content images using the Image button.";
        } else if (form.status == "scheduled" && !ContentTypes.supports(type, "schedule")) {
            error = "This collection does not support scheduled publication.";
        } else if (form.status == "scheduled"
            && (form.scheduled_epoch <= Date.now().getTime()
                || form.scheduled_epoch > Date.now().getTime() + 315360000000.0)) {
            error = "Choose a future site time within the next ten years.";
        }
        var date = ContentItemData.dateValue(form.published_at);
        if (date != "") {
            var validDate = ~/^\d{4}-\d{2}-\d{2}$/.match(date);
            try {
                validDate = validDate
                    && DateTools.format(Date.fromString('${date} 12:00:00'), "%Y-%m-%d") == date;
            } catch (invalidDate:Dynamic) {
                validDate = false;
            }
            if (!validDate) {
                error = "Enter a valid site date.";
            }
        }
        var expected = AdminController.input(request, "version", 16);
        if (expected != ""
            && (!~/^[1-9][0-9]*$/.match(expected)
                || (existing != null && Std.parseInt(expected) != existing.version))) {
            return ContentController.editor(request, form.toObject(),
                "This content changed in another editor. Reload the saved version before saving.",
                409);
        }
        if (error == ""
            && ContentItem.query.where("content_type", kind)
                .where("slug", form.slug)
                .where("id", "!=", id)
                .exists()) {
            error = "Another content item already uses this slug. Choose another one.";
        }
        if (error != "") {
            return ContentController.editor(request, form.toObject(), error, 422);
        }
        var previousTags = id == 0 ? [] : TagData.forContent(id);
        var requested:Dynamic = request.input("tags", null);
        var tags = !ContentTypes.supports(type, "tags")
            || requested == null ? previousTags : TagData.parse(requested);
        var customFields:Dynamic = {};
        try {
            var previousValues = id == 0 ? {} : ContentFields.values(id, type);
            var suppliedValues = ContentFields.decode(request.input("custom_fields", null),
                previousValues);
            customFields = ContentFields.validate(type, suppliedValues, form.status != "draft");
        } catch (invalidFields:Dynamic) {
            error = Std.string(invalidFields);
        }
        if (tags == null) {
            error = "Choose up to 10 existing tags.";
        }
        if (error != "") {
            return ContentController.editor(request, form.toObject(), error, 422);
        }
        form.reading_minutes = ContentItemData.readingMinutes(form.content);
        var prepared = form.toObject();
        prepared.tags = tags;
        prepared.fields = customFields;
        try {
            var pluginError = PluginRuntime.saving(prepared);
            if (pluginError != "") {
                return ContentController.editor(request, form.toObject(), pluginError, 422);
            }
        } catch (pluginError:Dynamic) {
            return ContentController.editor(request, form.toObject(),
                'A content plugin could not validate this save: ${Std.string(pluginError)}', 422);
        }
        var data = request.only("title", "slug", "excerpt", "content", "category", "image",
            "image_alt", "seo_title", "seo_description");
        data.set("title", form.title);
        data.set("slug", form.slug);
        data.set("excerpt", form.excerpt);
        data.set("content", form.content);
        data.set("category", form.category);
        data.set("image", form.image);
        data.set("image_alt", form.image_alt);
        data.set("seo_title", form.seo_title);
        data.set("seo_description", form.seo_description);
        data.set("content_type", kind);
        data.set("author_id", form.author_id);
        data.set("version", existing == null ? 1 : existing.version + 1);
        data.set("status", form.status);
        data.set("featured", form.featured);
        data.set("reading_minutes", form.reading_minutes);
        var scheduledEpoch:Float = 0.0;
        if (form.status == "scheduled") {
            scheduledEpoch = form.scheduled_epoch;
        }
        data.set("scheduled_epoch", scheduledEpoch);
        data.set("published_at", date == "" ? SiteSettingsStore.timestamp().substr(0, 10) : date);
        data.set("updated_at", SiteSettingsStore.timestamp());
        var saved:ContentItem = existing;
        try {
            MediaLocks.run(() -> {
                if ((form.image != "" && !MediaReferences.storedImage(form.image))
                    || !MediaStorage.contentUsesStoredImages(form.content)) {
                    throw new Exception("An image is no longer available. Upload it again before saving.");
                }
                DBStatic.transaction(() -> {
                    if (existing != null) {
                        ContentHistory.remember(existing, previousTags, admin.id);
                    }
                    if (form.featured == 1 && form.status == "published") {
                        ContentItem.query.where("content_type", kind)
                            .where("featured", 1)
                            .update(["featured" => 0]);
                    }
                    if (existing == null) {
                        data.set("created_at", SiteSettingsStore.timestamp());
                        saved = ContentItem.query.create(data);
                    } else {
                        existing.update(data);
                    }
                    TagData.assign(saved.id, tags);
                    ContentFields.save(saved.id, type, customFields);
                    ContentHistory.remember(saved, tags, admin.id);
                    WorkingCopies.clear(admin.id, saved.id, kind);
                    var newKey = AdminController.input(request, "draft_key", 128);
                    if (existing == null && newKey != "") {
                        WorkingCopies.consume(admin.id, saved.id, kind, newKey);
                    }
                    Activity.record(existing == null ? "created" : "saved", kind, saved.id,
                        saved.title);
                });
                return true;
            });
        } catch (saveError:Dynamic) {
            return ContentController.editor(request, form.toObject(),
                "The content could not be saved. Check its slug and tag assignments, then try again.",
                422);
        }
        ContentCache.contentChanged();
        var savedData:Dynamic = saved.toObject();
        savedData.fields = customFields;
        PluginRuntime.saved(savedData);
        var base = ContentController.base(kind);
        var stay = request.input("stay", "0") == "1";
        var location = stay ? '${base}/${saved.id}/edit?notice=saved' : '${base}?notice=saved';
        return ResponseBuilder.asRedirect(location, 303);
    }
}
