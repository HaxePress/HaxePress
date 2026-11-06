package hx.press;

import hx.press.CategoryData;
import hx.press.ContentItemData;
import hx.press.plugins.PluginRuntime;
import hx.well.facades.Inertia;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.press.model.ActivityLog;
import hx.press.content.ContentTypes;

class DashboardController {
    public static function index(request:Request):AbstractResponse {
        var admin = CmsAccess.current();
        var author = CmsAccess.can("edit_others") ? 0 : admin.id;
        var capabilities = CmsAccess.capabilities(admin.role);
        var published = ContentData.count("", "", "published", author, capabilities);
        var drafts = ContentData.count("", "", "draft", author, capabilities);
        var scheduled = ContentData.count("", "", "scheduled", author, capabilities);
        var topics = CmsAccess.can("taxonomy") ? CategoryData.count() : 0;
        var recent = ContentData.recent(author, capabilities)
            .map(item -> ContentItemData.adminSummary(item));
        var collections = ContentTypes.dashboard(author, capabilities);
        var collectionCount = ContentTypes.dashboardCount(capabilities);
        var entries:Array<Dynamic> = CmsAccess.can("activity") ? ActivityLog.query.select(["id", "actor", "action", "entity", "label", "created_at"])
            .orderBy("id", "DESC")
            .limit(5)
            .get()
            .map(model -> cast model.toObject()) : [];
        var summary = {
            published: published,
            drafts: drafts,
            collections: collectionCount,
            scheduled: scheduled
        };
        var widgets = PluginRuntime.blocks("dashboard.widgets", {summary: summary});
        var props = {
            published: published,
            drafts: drafts,
            topics: topics,
            items: recent,
            collections: collectionCount,
            scheduled: scheduled,
            activity: entries,
            widgets: widgets,
            collectionCards: collections
        };
        return Inertia.render("Admin/Dashboard", props);
    }
}
