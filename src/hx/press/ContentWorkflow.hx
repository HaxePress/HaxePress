package hx.press;

import hx.press.content.ContentLocks;
import hx.press.ContentCache;
import hx.press.SiteSettingsStore;
import hx.press.plugins.PluginRuntime;
import hx.press.validation.PositiveInt;
import hx.well.facades.DBStatic;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.ResponseBuilder;
import hx.press.model.ContentItem;
import hx.press.content.ContentTypes;
import hx.press.model.ContentType;

class ContentWorkflow {
    public static function change(request:Request, kind:String, restore:Bool):AbstractResponse {
        if (!ContentTypes.exists(kind)) {
            return SiteController.notFound(request);
        }
        var id = PositiveInt.route(request, "id");
        return ContentLocks.run('document-${id}', () -> {
            var document = ContentItem.query.select([
                "id",
                "author_id",
                "status",
                "previous_status",
                "scheduled_epoch",
                "version",
                "title"
            ]).where("id", id).where("content_type", kind).limit(1).first();
            if (document == null || !CmsAccess.canCollection(kind)
                || !CmsAccess.canEdit(document.author_id)) {
                return CmsController.forbidden(request);
            }
            if (restore && document.status != "trash") {
                return ResponseBuilder.asJson({error: "Only trashed content can be restored."},
                    422);
            }
            if (!restore
                && !CmsAccess.can("publish")
                && document.status != "draft"
                && document.status != "trash") {
                return CmsController.forbidden(request);
            }
            if (!restore && document.status == "trash") {
                return ResponseBuilder.asRedirect('${ContentController.base(kind)}?status=trash',
                    303);
            }
            var status = "trash";
            if (restore) {
                status = ["published", "draft", "scheduled"].contains(document.previous_status) ? document.previous_status : "draft";
                if (!CmsAccess.can("publish")
                    || (status == "scheduled" && document.scheduled_epoch <= Date.now()
                        .getTime())) {
                    status = "draft";
                }
            }
            var values:Map<String, Dynamic> = [
                "status" => status,
                "version" => document.version + 1,
                "updated_at" => SiteSettingsStore.timestamp(),
                "featured" => 0
            ];
            if (!restore) {
                values.set("previous_status", document.status);
            }
            DBStatic.transaction(() -> {
                document.update(values);
                Activity.record(restore ? "restored" : "trashed", kind, id, document.title);
            });
            ContentCache.contentChanged();
            var notice = restore ? "restored" : "trashed";
            return ResponseBuilder.asRedirect('${ContentController.base(kind)}?notice=${notice}',
                303);
        });
    }

    public static function publishDue(capabilities:Array<String> = null, author:Int = 0):Int {
        var types = ContentType.query.select(["key"]);
        if (capabilities == null) {
            ContentTypes.available(types);
        } else {
            ContentTypes.accessible(types, capabilities);
        }
        var due = ContentItem.query.select(["id"])
            .whereInQuery("content_type", types)
            .where("status", "scheduled")
            .where("scheduled_epoch", ">", 0)
            .where("scheduled_epoch", "<=", Date.now().getTime())
            .orderBy("scheduled_epoch")
            .orderBy("id")
            .limit(50);
        if (author > 0) {
            due.where("author_id", author);
        }
        var rows = due.get();
        var count = 0;
        for (item in rows) {
            var published = ContentLocks.run('document-${item.id}', () -> {
                var document = ContentItem.query.select(["id", "content_type", "title", "version", "featured", "language"])
                    .where("id", item.id)
                    .where("status", "scheduled")
                    .where("scheduled_epoch", "<=", Date.now().getTime())
                    .limit(1)
                    .first();
                if (document == null) {
                    return false;
                }
                DBStatic.transaction(() -> {
                    if (document.featured == 1) {
                        ContentItem.query.where("content_type", document.content_type)
                            .where("language", document.language)
                            .where("featured", 1)
                            .update(["featured" => 0]);
                    }
                    document.update([
                        "status" => "published",
                        "featured" => document.featured,
                        "version" => document.version + 1,
                        "updated_at" => SiteSettingsStore.timestamp()
                    ]);
                    Activity.append(0, "Scheduler", "published", document.content_type,
                        document.id, document.title);
                });
                PluginRuntime.saved({
                    id: document.id,
                    title: document.title,
                    status: "published",
                    content_type: document.content_type,
                    version: document.version
                });
                return true;
            });
            if (published) {
                count++;
                ContentCache.contentChanged();
            }
        }
        if (count > 0) {
            ContentCache.contentChanged();
        }
        return count;
    }

    public static function runDue(request:Request):AbstractResponse {
        if (!CmsAccess.can("publish")) {
            return CmsController.forbidden(request);
        }
        var admin = CmsAccess.current();
        var count = publishDue(CmsAccess.capabilities(admin.role),
            CmsAccess.can("edit_others") ? 0 : admin.id);
        return ResponseBuilder.asJson({published: count});
    }
}
