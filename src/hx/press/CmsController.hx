package hx.press;

import hx.press.AdminController;
import hx.press.SiteController;
import hx.press.ContentCache;
import hx.press.Pagination;
import hx.press.SiteSettingsStore;
import hx.well.facades.DBStatic;
import hx.well.facades.Inertia;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.ResponseBuilder;
import hx.press.model.ContentTag;
import hx.press.model.Tag;

using StringTools;

class CmsController {
    public static function forbidden(request:Request):AbstractResponse {
        return Inertia.render("Admin/Forbidden",
            {message: "Your account does not have access to this area."})
            .status(403);
    }

    public static function tags(request:Request, error:String = "",
            status:Int = 200):AbstractResponse {
        if (!CmsAccess.can("taxonomy")) {
            return forbidden(request);
        }
        var redirect = AdminController.validationRedirect(request, "tag", error, "/admin/tags");
        if (redirect != null) {
            return redirect;
        }
        var search = request.query("q", "").trim().substr(0, 80);
        var cursor = Pagination.cursor(request);
        var page = TagData.page(search, cursor);
        var total = TagData.count(search);
        var links = Pagination.links("/admin/tags", ["q" => search], page, cursor, total,
            tag -> tag.id, tag -> null);
        var notice = switch (request.query("notice", "")) {
            case "saved": "The tag has been saved.";
            case "deleted": "The tag and its content assignments have been removed.";
            default: "";
        };
        var props:Map<String, Dynamic> = [
            "tags" => page.items,
            "total" => total,
            "query" => search,
            "pagination" => links,
            "notice" => notice
        ];
        if (error != "") {
            props.set("errors", ["tag" => error]);
        }
        return Inertia.render("Admin/Tags", props).status(status);
    }

    public static function deleteTag(request:Request):AbstractResponse {
        if (!CmsAccess.can("taxonomy")) {
            return forbidden(request);
        }
        var id = Std.parseInt(request.route("id"));
        var tag = Tag.query.select(["id", "name"]).where("id", id).limit(1).first();
        if (tag != null) {
            DBStatic.transaction(() -> {
                ContentTag.query.where("tag_id", id).delete();
                tag.delete();
                Activity.record("deleted", "tag", tag.id, tag.name);
            });
            ContentCache.changed("tags");
            ContentCache.contentChanged();
        }
        return ResponseBuilder.asRedirect("/admin/tags?notice=deleted", 303);
    }

    public static function tagOptions(request:Request):AbstractResponse {
        var options = TagData.options(request.query("q", "").substr(0, 80));
        return ResponseBuilder.asJson({tags: options});
    }

    public static function tagArchive(request:Request):AbstractResponse {
        var tag = TagData.named(request.route("slug"));
        if (tag == null) {
            return SiteController.notFound(request);
        }
        var primaryType = SiteSettingsStore.settings().get("home_type") ?? "entry";
        return SiteController.index(request, request.query("type", primaryType), tag);
    }
}
