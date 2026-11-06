package hx.press;

import hx.press.AdminController;
import hx.press.SiteController;
import hx.press.CategoryData;
import hx.press.Pagination;
import hx.press.ContentItemData;
import hx.press.data.ContentItemRecord;
import haxe.Json;
import hx.well.facades.Inertia;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.ResponseBuilder;
import hx.press.model.ContentItem;
import hx.press.model.ContentRevision;
import hx.press.model.EditorDraft;
import hx.press.content.ContentTypes;
import hx.press.content.ContentFields;
import hx.press.content.ContentTypeDefinition;

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
        var props = {
            items: page.items.map(item -> ContentItemData.adminSummary(item, type)),
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
            workingDrafts: drafts
        };
        return Inertia.render("Admin/Content", props);
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
        var item = ContentData.detail(Std.parseInt(request.route("id")), kind);
        return item == null ? SiteController.notFound(request) : renderEditor(request, item, type);
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
        var url = isNew ? '${type.adminBase}/new' : '${type.adminBase}/${item.id}/edit';
        var redirect = AdminController.validationRedirect(request, "content", error, url);
        if (redirect != null) {
            return redirect;
        }
        var admin = CmsAccess.current();
        var draftKey = item.id > 0 ? WorkingCopies.key(admin.id, kind,
            item.id) : request.query("draft", "");
        if (item.id == 0 && !StringTools.startsWith(draftKey, 'draft-${admin.id}-${kind}-')) {
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
        var props:Map<String, Dynamic> = [
            "item" => detail,
            "kind" => kind,
            "contentType" => type,
            "isNew" => isNew,
            "hasCategories" => hasCategories,
            "categories" => options,
            "draftKey" => draftKey,
            "workingCopy" => working,
            "canPublish" => CmsAccess.can("publish"),
            "notice" => request.query("notice", "") == "saved" ? "Your content has been saved." : ""
        ];
        if (error != "") {
            props.set("errors", ["content" => error]);
        }
        return Inertia.render("Admin/Editor", props).status(status);
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
        var id = Std.parseInt(request.route("id")) ?? 0;
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
        var id = Std.parseInt(request.route("id"));
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
        var id = Std.parseInt(request.route("id"));
        if (!owned(id, kind)) {
            return CmsController.forbidden(request);
        }
        var revisionId = Std.parseInt(request.route("revision"));
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
