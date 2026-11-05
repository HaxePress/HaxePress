package hx.press;

import hx.press.AdminController;
import hx.press.Pagination;
import hx.well.facades.Inertia;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.ResponseBuilder;
import hx.press.model.MediaAsset;
import hx.press.media.MediaUsage;
import hx.press.media.MediaReferenceReport;
import haxe.Exception;
import hx.well.facades.Storage;

class MediaController {
    public static function index(request:Request, error:String = "",
            status:Int = 200):AbstractResponse {
        if (!CmsAccess.can("media")) {
            return CmsController.forbidden(request);
        }
        var search = StringTools.trim(request.query("q", "")).substr(0, 100);
        var cursor = Pagination.cursor(request);
        var page = MediaCatalog.page(search, cursor);
        var total = MediaCatalog.count(search);
        var links = Pagination.links("/admin/media", ["q" => search], page, cursor, total,
            image -> image.id, image -> null);
        var images = page.items.map(image -> {
            var data:Dynamic = Reflect.copy(image);
            data.url = Storage.disk("media").url(image.filename);
            return data;
        });
        if (request.query("format", "") == "json") {
            return ResponseBuilder.asJson({images: images, pagination: links, total: total});
        }
        var libraryImages = images.map(image -> {
            var data:Dynamic = Reflect.copy(image);
            data.references_verified = true;
            try {
                data.can_delete = !MediaUsage.used(image.id, image.filename);
            } catch (_:Exception) {
                data.can_delete = false;
                data.references_verified = false;
            }
            return data;
        });
        var redirect = AdminController.validationRedirect(request, "media", error, "/admin/media");
        if (redirect != null) {
            return redirect;
        }
        var notice = request.query("notice",
            "") == "saved" ? "Image details have been saved." : request.query("notice",
                "") == "deleted" ? "The image has been deleted." : "";
        var props:Map<String, Dynamic> = [
            "images" => libraryImages,
            "pagination" => links,
            "total" => total,
            "query" => search,
            "notice" => notice
        ];
        if (error != "") {
            props.set("errors", ["media" => error]);
        }
        return Inertia.render("Admin/Media", props).status(status);
    }

    public static function references(request:Request):AbstractResponse {
        if (!CmsAccess.can("media")) {
            return ResponseBuilder.asJson({error: "Your account cannot access the media library."},
                403);
        }
        var id = Std.parseInt(request.route("id"));
        var image = MediaAsset.query.select(["id", "filename"]).where("id", id).first();
        if (image == null) {
            return ResponseBuilder.asJson({error: "Image not found."}, 404);
        }
        var canDelete = false;
        var verified = true;
        try {
            canDelete = !MediaUsage.used(image.id, image.filename);
        } catch (_:Exception) {
            verified = false;
        }
        try {
            var page = MediaReferenceReport.page(image.id, image.filename,
                request.query("source", "content"), request.query("after", ""));
            var props = {
                items: page.items,
                next: page.next,
                canDelete: canDelete && verified && page.verified,
                verified: verified && page.verified};
            return ResponseBuilder.asJson(props).header("Cache-Control", "private, no-store");
        } catch (error:Exception) {
            return ResponseBuilder.asJson({error: error.message}, 422);
        }
    }

    public static function delete(request:Request):AbstractResponse {
        if (!CmsAccess.can("media")) {
            return CmsController.forbidden(request);
        }
        try {
            MediaCatalog.remove(Std.parseInt(request.route("id")));
            return ResponseBuilder.asRedirect("/admin/media?notice=deleted", 303);
        } catch (error:Dynamic) {
            return index(request, Std.string(error), 422);
        }
    }
}
