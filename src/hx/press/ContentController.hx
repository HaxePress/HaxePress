package hx.press;

import hx.press.AdminController;
import hx.press.SiteController;
import hx.press.CategoryData;
import hx.press.Pagination;
import hx.press.ContentItemData;
import hx.press.data.ContentItemRecord;
import hx.press.validation.PositiveInt;
import hx.press.view.ContentAdminRows;
import hx.press.view.View;
import haxe.Json;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.ResponseBuilder;
import hx.press.model.ContentItem;
import hx.press.model.ContentRevision;
import hx.press.model.EditorDraft;
import hx.press.content.ContentTypes;
import hx.press.content.ContentFields;
import hx.press.content.ContentTypeDefinition;
import hx.press.i18n.I18n;
import hx.press.packages.ThemeData;
import hx.well.validator.ValidatorRule;

class ContentController {
    public static function base(kind:String):String {
        return ContentTypes.adminBase(kind);
    }

    public static function index(request:Request, kind:String):AbstractResponse {
        var type = ContentTypes.find(kind);
        if (type == null) {
            return SiteController.notFound(request);
        }
        if (!CmsAccess.can(type.capability)) {
            return CmsController.forbidden(request);
        }
        var admin = CmsAccess.current();
        var author = CmsAccess.can("edit_others") ? 0 : admin.id;
        var search = StringTools.trim(request.query("q", "")).substr(0, 120);
        var status = request.query("status", "");
        if (!["", "draft", "published", "scheduled", "trash"].contains(status)) {
            status = "";
        }
        var cursor = Pagination.cursor(request);
        var page = ContentData.page(kind, search, status, author, cursor);
        var count = ContentData.count(kind, search, status, author);
        var links = Pagination.links(type.adminBase, ["q" => search, "status" => status], page,
            cursor, count, document -> document.id,
            document -> ContentItemData.dateValue(document.updated_at));
        var drafts = EditorDraft.query.select(["key", "title", "updated_at"])
            .where("user_id", admin.id)
            .where("kind", kind)
            .where("document_id", 0)
            .where("expires_epoch", ">", Date.now().getTime())
            .orderBy("updated_at", "DESC")
            .limit(5)
            .get()
            .map(model -> cast model.toObject());
        var notice = switch (request.query("notice", "")) {
            case "saved": "Your content has been saved.";
            case "trashed": "The content has been moved to the trash.";
            case "restored": "The content has been restored.";
            case "deleted": "The content has been permanently deleted.";
            default: "";
        };
        var listFields = ContentAdminRows.listFields(type);
        var items = page.items.map(item ->
            ContentAdminRows.withColumns(ContentItemData.adminSummary(item, type), listFields));
        var props = {
            items: items,
            query: search,
            status: status,
            total: ContentData.count(kind, "", "", author),
            published: ContentData.count(kind, "", "published", author),
            drafts: ContentData.count(kind, "", "draft", author),
            scheduled: ContentData.count(kind, "", "scheduled", author),
            trash: ContentData.count(kind, "", "trash", author),
            pagination: links,
            notice: notice,
            kind: kind,
            contentType: type,
            listFields: listFields,
            showCategory: ContentTypes.supports(type, "categories"),
            workingDrafts: drafts
        };
        return View.render("Admin/Content", props);
    }

    public static function newDocument(request:Request, kind:String):AbstractResponse {
        var type = ContentTypes.find(kind);
        if (type == null) {
            return SiteController.notFound(request);
        }
        if (!CmsAccess.can(type.capability)) {
            return CmsController.forbidden(request);
        }
        var item = new ContentItem();
        item.content_type = kind;
        item.author_id = CmsAccess.current().id;
        item.category = ContentTypes.supports(type, "categories") ? CategoryData.firstName() : "";
        return renderEditor(request, item.toObject(), type);
    }

    public static function edit(request:Request, kind:String):AbstractResponse {
        var type = ContentTypes.find(kind);
        if (type == null) {
            return SiteController.notFound(request);
        }
        var item = ContentData.detail(PositiveInt.route(request, "id"), kind);
        return item == null ? SiteController.notFound(request) : renderEditor(request, item, type);
    }

    public static function preview(request:Request, kind:String):AbstractResponse {
        var type = ContentTypes.find(kind);
        if (type == null) {
            return SiteController.notFound(request);
        }
        if (!CmsAccess.can(type.capability)) {
            return CmsController.forbidden(request);
        }
        if (!request.validate([
            "id" => [String, Max(10)],
            "title" => [String, Max(180)],
            "slug" => [String, Max(180)],
            "excerpt" => [String, Max(500)],
            "content" => [String, Max(100000)],
            "category" => [String, Max(80)],
            "image" => [String, Max(2000)],
            "image_alt" => [String, Max(500)],
            "status" => [String, Max(30)],
            "featured" => [String, Max(1)],
            "published_at" => [String, Max(50)],
            "tags" => [String, Max(1000)],
            "seo_title" => [String, Max(200)],
            "seo_description" => [String, Max(500)],
            "scheduled_epoch" => [String, Max(32)],
            "custom_fields" => [String, Max(64000)]
        ])) {
            return previewError("The preview exceeds the editor limits.");
        }
        var rawId:String = request.input("id", "");
        var id = Std.parseInt(rawId) ?? 0;
        if (rawId != "" && (id <= 0 || Std.string(id) != rawId)) {
            return SiteController.notFound(request);
        }
        var existing:Null<ContentItem> = null;
        if (id > 0) {
            existing = ContentItem.query.select(["author_id", "version"])
                .where("id", id)
                .where("content_type", kind)
                .first();
            if (existing == null) {
                return SiteController.notFound(request);
            }
            if (!CmsAccess.canEdit(existing.author_id)) {
                return CmsController.forbidden(request);
            }
        }
        var tags = ContentTypes.supports(type,
            "tags") ? TagData.parse(request.input("tags", "")) : [];
        if (tags == null) {
            return previewError("Choose up to 10 existing tags.");
        }
        var fields:Dynamic;
        try {
            fields = ContentFields.validate(type, request.input("custom_fields", null), false);
        } catch (invalid:Dynamic) {
            return previewError(Std.string(invalid));
        }
        var draft = ContentItemData.fromEditor(request, type, id, existing);
        draft.reading_minutes = ContentItemData.readingMinutes(draft.content);
        draft.updated_at = SiteSettingsStore.timestamp();
        if (ContentItemData.dateValue(draft.published_at) == "") {
            draft.published_at = SiteSettingsStore.timestamp().substr(0, 10);
        }
        var settings = SiteSettingsStore.settings();
        var home = id > 0 && settings.get("home_mode") == "page"
            && Std.string(id) == settings.get("home_page");
        var path = type.publicBase;
        if (home) {
            path = "/";
        } else if (draft.slug != "") {
            path = '${path}/${StringTools.urlEncode(draft.slug)}';
        }
        View.shareAll(SiteController.appearance(ThemeData.active(), path));
        return SiteController.renderDocument(request, draft.toObject(), type, home, {
            tags: tags,
            fields: fields
        });
    }

    static function previewError(message:String):AbstractResponse {
        return ResponseBuilder.asString(I18n.t(message), 422)
            .header("Content-Type", "text/plain; charset=utf-8");
    }

    public static function editor(request:Request, item:ContentItemRecord, error:String = "",
            status:Int = 200):AbstractResponse {
        var type = ContentTypes.find(item.content_type);
        if (type == null) {
            return SiteController.notFound(request);
        }
        return renderEditor(request, item, type, error, status);
    }

    static function renderEditor(request:Request, item:ContentItemRecord,
            type:ContentTypeDefinition, error:String = "", status:Int = 200):AbstractResponse {
        var kind = item.content_type;
        if (!CmsAccess.can(type.capability)
            || (item.id > 0 && !CmsAccess.canEdit(item.author_id ?? 0))) {
            return CmsController.forbidden(request);
        }
        var isNew = item.id == 0;
        var admin = CmsAccess.current();
        var draftPrefix = 'draft-${admin.id}-${kind}-';
        var submittedDraft = AdminController.input(request, "draft_key", 128);
        var keepsDraft = isNew && StringTools.startsWith(submittedDraft, draftPrefix);
        var newUrl = keepsDraft ? '${type.adminBase}/new?draft=${StringTools.urlEncode(submittedDraft)}' : '${type.adminBase}/new';
        var url = isNew ? newUrl : '${type.adminBase}/${item.id}/edit';
        var redirect = AdminController.validationRedirect(request, "content", error, url);
        if (redirect != null) {
            return redirect;
        }
        var draftKey = item.id > 0 ? WorkingCopies.key(admin.id, kind,
            item.id) : request.query("draft", "");
        if (item.id == 0 && !StringTools.startsWith(draftKey, draftPrefix)) {
            draftKey = WorkingCopies.freshKey(admin.id, kind);
        }
        var working = WorkingCopies.find(admin.id, kind, item.id, draftKey);
        var supportsCategories = ContentTypes.supports(type, "categories");
        var options = supportsCategories ? CategoryData.options("") : [];
        var hasCategories = !supportsCategories || options.length > 0;
        if (item.category != "" && !options.contains(item.category)) {
            options.push(item.category);
        }
        var detail = ContentItemData.detail(item);
        if (error != "") {
            try {
                detail.fields = ContentFields.decode(request.input("custom_fields", null),
                    detail.fields);
            } catch (_:Dynamic) {}
        }
        var canPublish = CmsAccess.can("publish");
        var notice = request.query("notice", "") == "saved" ? "Your content has been saved." : "";
        var editor = ContentEditorData.view(request, {
            detail: detail,
            type: type,
            isNew: isNew,
            hasCategories: hasCategories,
            categories: options,
            draftKey: draftKey,
            workingCopy: working,
            canPublish: canPublish,
            notice: notice
        });
        var props:Map<String, Dynamic> = [
            "item" => detail,
            "kind" => kind,
            "contentType" => type,
            "isNew" => isNew,
            "hasCategories" => hasCategories,
            "categories" => options,
            "draftKey" => draftKey,
            "workingCopy" => working,
            "canPublish" => canPublish,
            "notice" => notice,
            "editor" => editor
        ];
        if (error != "") {
            props.set("errors", ["content" => error]);
        }
        return View.render("Admin/Editor", props).status(status);
    }

    public static function owned(id:Int, kind:String, ?version:Int):Bool {
        var admin = CmsAccess.current();
        if (admin == null || !CmsAccess.canCollection(kind)) {
            return false;
        }
        var query = ContentItem.query.where("id", id).where("content_type", kind);
        if (!CmsAccess.can("edit_others")) {
            query.where("author_id", admin.id);
        }
        if (version != null) {
            query.where("version", version);
        }
        return query.exists();
    }

    public static function discardWorking(request:Request, kind:String):AbstractResponse {
        var id = PositiveInt.route(request, "id");
        if (!CmsAccess.canCollection(kind) || (id > 0 && !owned(id, kind))) {
            return CmsController.forbidden(request);
        }
        WorkingCopies.clear(CmsAccess.current().id, id, kind,
            AdminController.input(request, "draft_key", 128));
        return
            ResponseBuilder.asRedirect(id > 0 ? '${base(kind)}/${id}/edit' : '${base(kind)}/new',
                303);
    }

    public static function history(request:Request, kind:String):AbstractResponse {
        if (!ContentTypes.supports(ContentTypes.find(kind), "revisions")) {
            return SiteController.notFound(request);
        }
        var id = PositiveInt.route(request, "id");
        if (!owned(id, kind)) {
            return ResponseBuilder.asJson({error: "This history is not available."}, 403);
        }
        var revisions:Array<Dynamic> = ContentRevision.query.select([
            "content_revisions.id AS id",
            "content_revisions.version AS version",
            "content_revisions.title AS title",
            "content_revisions.created_at AS created_at",
            "admins.name AS author"
        ])
            .leftJoin("admins", "content_revisions.author_id", "=", "admins.id")
            .where("document_id", id)
            .orderBy("version", "DESC")
            .limit(50)
            .get()
            .map(model -> cast model.toObject());
        return ResponseBuilder.asJson({revisions: revisions});
    }

    public static function revision(request:Request, kind:String,
            restore:Bool = false):AbstractResponse {
        var id = PositiveInt.route(request, "id");
        if (!owned(id, kind)) {
            return CmsController.forbidden(request);
        }
        var revisionId = PositiveInt.route(request, "revision");
        var revision = ContentRevision.query.select(["id", "snapshot"])
            .where("id", revisionId)
            .where("document_id", id)
            .limit(1)
            .first();
        if (revision == null) {
            return SiteController.notFound(request);
        }
        var snapshot:Dynamic = Json.parse(revision.snapshot);
        if (!restore) {
            return ResponseBuilder.asJson({snapshot: snapshot});
        }
        var document = ContentItem.query.select(["version"]).where("id", id).limit(1).first();
        var admin = CmsAccess.current();
        snapshot.tagRecords = snapshot.tags;
        var tags:Array<Dynamic> = snapshot.tags ?? [];
        snapshot.tags = [for (tag in tags) Std.string(tag.id)].join(",");
        snapshot.custom_fields = Json.stringify(snapshot.fields ?? {});
        WorkingCopies.clear(admin.id, id, kind);
        WorkingCopies.save(admin.id, kind, id, "", 1, document.version, snapshot);
        return ResponseBuilder.asRedirect('${base(kind)}/${id}/edit?notice=revision', 303);
    }
}
