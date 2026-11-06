package hx.press.content;

import hx.press.CmsAccess;
import hx.press.model.ContentItem;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.ResponseBuilder;

class ContentOptions {
    public static function published(request:Request):AbstractResponse {
        if (!CmsAccess.can("settings") && !CmsAccess.can("navigation")
            && !CmsAccess.hasContentAccess()) {
            return ResponseBuilder.asJson({error: "Access restricted."}, 403);
        }
        var search = StringTools.trim(request.query("q", "")).substr(0, 100);
        var query = ContentItem.query.select(["id", "title", "slug", "content_type"])
            .where("status", "published")
            .whereInQuery("content_type", ContentTypes.publicKeys());
        var kind = request.query("type", "");
        if (kind != "") {
            query.where("content_type", kind);
        }
        if (search != "") {
            var escaped = StringTools.replace(StringTools.replace(StringTools.replace(search, "!",
                "!!"), "%", "!%"), "_", "!_");
            var pattern = '%${escaped}%';
            query.whereLike("title", pattern);
        }
        var rows:Array<{
            id:Int,
            title:String,
            slug:String,
            content_type:String
        }> = query.orderBy("title")
            .orderBy("id")
            .limit(20)
            .get()
            .map(model -> cast model.toObject());
        var selected = Std.parseInt(request.query("selected", "0")) ?? 0;
        var hasSelected = selected == 0;
        for (row in rows) {
            if (row.id == selected) {
                hasSelected = true;
                break;
            }
        }
        if (!hasSelected) {
            var selectedItem = ContentItem.query.select(["id", "title", "slug", "content_type"])
                .where("id", selected)
                .where("status", "published")
                .whereInQuery("content_type", ContentTypes.publicKeys())
                .first();
            if (selectedItem != null) {
                rows.push(cast selectedItem.toObject());
            }
        }
        var options = [
            for (row in rows)
                {
                    id: row.id,
                    title: row.title,
                    url: ContentTypes.url(row.content_type, row.slug),
                    content_type: row.content_type
                }
        ];
        return ResponseBuilder.asJson({items: options});
    }
}
