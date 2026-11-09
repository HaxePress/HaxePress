package hx.press;

import hx.press.i18n.SiteTexts;
import hx.press.AdminController;
import hx.press.SiteController;
import hx.press.ContentCache;
import hx.press.Pagination;
import hx.press.SiteSettingsStore;
import hx.press.validation.PositiveInt;
import hx.well.facades.DBStatic;
import hx.press.view.View;
import hx.press.AdminForms;
import hx.press.TagData.TagRecord;
import hx.press.TagData.TagSummary;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.ResponseBuilder;
import hx.press.model.ContentTag;
import hx.press.model.Tag;

using StringTools;

typedef TagFormRecord = {
    var id:String;
    var name:String;
    var slug:String;
    var description:String;
}

class CmsController {
    public static function forbidden(request:Request):AbstractResponse {
        var props = {message: "Your account does not have access to this area."};
        return View.render("Admin/Forbidden", props).status(403);
    }

    public static function tags(request:Request, error:String = "",
            status:Int = 200):AbstractResponse {
        if (!CmsAccess.can("taxonomy")) {
            return forbidden(request);
        }
        var returnUrl = AdminForms.returnUrl(request, "/admin/tags");
        var redirect = AdminController.validationRedirect(request, "tag", error, returnUrl);
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
        var tagForm = tagForm(request, page.items);
        var props:Map<String, Dynamic> = [
            "tags" => page.items,
            "total" => total,
            "query" => search,
            "pagination" => links,
            "notice" => notice,
            "tagForm" => tagForm
        ];
        if (error != "") {
            props.set("errors", ["tag" => error]);
        }
        return View.render("Admin/Tags", props).status(status);
    }

    /** The tag form: a failed submission, the tag in `?edit=`, or an empty form. **/
    static function tagForm(request:Request, listed:Array<TagSummary>):TagFormRecord {
        if (AdminForms.resubmitted(request, "name")) {
            return {
                id: AdminForms.old(request, "id", ""),
                name: AdminForms.old(request, "name", ""),
                slug: AdminForms.old(request, "slug", ""),
                description: AdminForms.old(request, "description", "")
            };
        }
        var editId = AdminForms.editId(request);
        var edited:Null<TagRecord> = Lambda.find(listed, tag -> tag.id == editId);
        if (edited == null && editId > 0) {
            var row = Tag.query.select(["id", "name", "slug", "description"])
                .where("id", editId)
                .limit(1)
                .first();
            edited = row == null ? null : cast row.toObject();
        }
        if (edited == null) {
            return {
                id: "",
                name: "",
                slug: "",
                description: ""
            };
        }
        return {
            id: Std.string(edited.id),
            name: edited.name,
            slug: edited.slug,
            description: edited.description ?? ""
        };
    }

    public static function deleteTag(request:Request):AbstractResponse {
        if (!CmsAccess.can("taxonomy")) {
            return forbidden(request);
        }
        var id = PositiveInt.route(request, "id");
        var tag = Tag.query.select(["id", "name"]).where("id", id).limit(1).first();
        if (tag != null) {
            DBStatic.transaction(() -> {
                ContentTag.query.where("tag_id", id).delete();
                tag.delete();
                SiteTexts.forget(['tag.${id}.name']);
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
