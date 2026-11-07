package hx.press.handler.admin.content;

import hx.press.content.ContentLocks;
import hx.press.ContentCache;
import hx.press.Activity;
import hx.press.CmsAccess;
import hx.press.CmsController;
import hx.press.validation.PositiveInt;
import hx.well.facades.DBStatic;
import hx.well.handler.AbstractHandler;
import hx.well.http.Request;
import hx.well.http.AbstractResponse;
import hx.well.http.ResponseBuilder;
import hx.press.model.ContentItem;
import hx.press.model.ContentTag;
import hx.press.model.ContentRevision;
import hx.press.model.EditorDraft;
import hx.press.model.MenuLink;
import hx.press.model.ContentValue;
import hx.press.content.ContentTypes;
import hx.press.ContentController;
import hx.press.SiteController;

class DeleteContentHandler extends AbstractHandler {
    final resolve:Request->String;
    final requireTrash:Bool;

    public function new(resolve:Request->String, requireTrash:Bool = false) {
        super();
        this.resolve = resolve;
        this.requireTrash = requireTrash;
    }

    public function execute(request:Request):AbstractResponse {
        var kind = resolve(request);
        if (!ContentTypes.exists(kind)) {
            return SiteController.notFound(request);
        }
        var id = PositiveInt.route(request, "id");
        return ContentLocks.run('document-${id}', () -> {
            var item = ContentItem.query.select(["id", "author_id", "status", "title"])
                .where("id", id)
                .where("content_type", kind)
                .limit(1)
                .first();
            if (item != null) {
                if (!CmsAccess.canCollection(kind) || !CmsAccess.canEdit(item.author_id)) {
                    return CmsController.forbidden(request);
                }
                if (requireTrash && item.status != "trash") {
                    return
                        ResponseBuilder.asJson({error: "Move this content to the trash before permanently deleting it."},
                        422);
                }
                if (!CmsAccess.can("publish") && item.status != "draft" && item.status != "trash") {
                    return CmsController.forbidden(request);
                }
                DBStatic.transaction(() -> {
                    ContentTag.query.where("content_id", item.id).delete();
                    ContentRevision.query.where("document_id", item.id).delete();
                    EditorDraft.query.where("document_id", item.id).delete();
                    ContentValue.query.where("content_id", item.id).delete();
                    MenuLink.query.where("content_id", item.id).delete();
                    item.delete();
                    Activity.record("deleted", kind, item.id, item.title);
                });
                ContentCache.contentChanged();
            }
            return ResponseBuilder.asRedirect('${ContentController.base(kind)}?notice=deleted',
                303);
        });
    }
}
