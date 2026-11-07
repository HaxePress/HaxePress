package hx.press;

import hx.press.AdminController;
import hx.press.Pagination;
import hx.press.validation.PositiveInt;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.ResponseBuilder;
import hx.well.http.ResponseStatic.abort;
import hx.press.model.MediaAsset;
import hx.press.media.MediaUsage;
import hx.press.media.MediaReferenceReport;
import hx.press.media.MediaReferences;
import hx.press.view.View;
import haxe.Exception;
import hx.well.facades.Storage;

class MediaController {
    public static function index(request:Request, error:String = "", status:Int = 200,
            returnUrl:String = "/admin/media"):AbstractResponse {
        if (!CmsAccess.can("media")) {
            return CmsController.forbidden(request);
        }
        var redirect = AdminController.validationRedirect(request, "media", error, returnUrl);
        if (redirect != null) {
            return redirect;
        }
        var search = StringTools.trim(request.query("q", "")).substr(0, 100);
        var trashed = request.query("status", "") == "trash";
        var cursor = Pagination.cursor(request);
        var page = MediaCatalog.page(search, cursor, trashed);
        var total = MediaCatalog.count(search, trashed);
        var parameters = trashed ? ["q" => search, "status" => "trash"] : ["q" => search];
        var links = Pagination.links("/admin/media", parameters, page, cursor, total,
            image -> image.id, image -> null);
        var images = page.items.map(image -> {
            var data:Dynamic = Reflect.copy(image);
            // Trashed files are not public; the library previews them through an admin route.
            data.url = trashed ? '/admin/media/${image.id}/trashed' : Storage.disk("media")
                .url(image.filename);
            return data;
        });
        if (request.query("format", "") == "json") {
            return ResponseBuilder.asJson({images: images, pagination: links, total: total});
        }
        var now = Date.now().getTime();
        var libraryImages = images.map(image -> {
            var data:Dynamic = Reflect.copy(image);
            data.references_verified = true;
            try {
                data.can_delete = !MediaUsage.used(image.id, image.filename);
            } catch (_:Exception) {
                data.can_delete = false;
                data.references_verified = false;
            }
            data.kilobytes = Std.int(Math.ceil(image.size / 1024));
            var remaining = MediaCatalog.expires(image.trashed_epoch) - now;
            data.days_left = trashed ? Std.int(Math.max(1,
                Math.ceil(remaining / (24 * 60 * 60 * 1000)))) : 0;
            return data;
        });
        // Images in use open the references dialog, which needs only these fields.
        var referenceImages = [
            for (image in libraryImages)
                if (image.can_delete != true) {
                    id: image.id,
                    filename: image.filename,
                    title: image.title,
                    alt: image.alt,
                    url: image.url,
                    canDelete: false,
                    verified: image.references_verified
                }
        ];
        var notices = [
            "saved" => "Image details have been saved.",
            "trashed" => "The image was moved to the trash.",
            "restored" => "The image was restored.",
            "deleted" => "The image was deleted permanently."
        ];
        var notice = notices.get(request.query("notice", "")) ?? "";
        var props:Map<String, Dynamic> = [
            "images" => libraryImages,
            "pagination" => links,
            "total" => total,
            "query" => search,
            "notice" => notice,
            "trashed" => trashed,
            "trashCount" => trashed ? total : MediaCatalog.count("", true),
            "trashDays" => MediaCatalog.TRASH_DAYS,
            "selectedImage" => trashed ? null : selectedImage(request, libraryImages),
            "referenceImages" => referenceImages,
            "mediaRules" => MediaReferences.rules()
        ];
        if (error != "") {
            props.set("errors", ["media" => error]);
        }
        return View.render("Admin/Media", props).status(status);
    }

    /** The image whose details are edited (`?edit=ID`), from this page or by its ID. **/
    static function selectedImage(request:Request, images:Array<Dynamic>):Dynamic {
        var editing = request.query("edit", "");
        var id = PositiveInt.parse(editing);
        if (id == null) {
            return null;
        }
        for (image in images) {
            if (image.id == id) {
                return image;
            }
        }
        var stored = MediaAsset.query.select(["id", "filename", "title", "alt"])
            .where("id", id)
            .where("trashed_epoch", 0)
            .limit(1)
            .first();
        if (stored == null) {
            return null;
        }
        return {
            id: stored.id,
            filename: stored.filename,
            title: stored.title,
            alt: stored.alt,
            url: Storage.disk("media").url(stored.filename)
        };
    }

    public static function references(request:Request):AbstractResponse {
        if (!CmsAccess.can("media")) {
            return ResponseBuilder.asJson({error: "Your account cannot access the media library."},
                403);
        }
        var id = PositiveInt.route(request, "id");
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

    public static function trash(request:Request):AbstractResponse {
        return change(request, MediaCatalog.trash, "/admin/media?notice=trashed", "/admin/media");
    }

    public static function restore(request:Request):AbstractResponse {
        return change(request, MediaCatalog.restore, "/admin/media?status=trash&notice=restored",
            "/admin/media?status=trash");
    }

    /** Deletes a trashed image permanently. Only people can do this; MCP clients cannot. **/
    public static function delete(request:Request):AbstractResponse {
        return change(request, MediaCatalog.remove, "/admin/media?status=trash&notice=deleted",
            "/admin/media?status=trash");
    }

    /** Shows a trashed image to people who manage media; trashed files have no public URL. **/
    public static function trashed(request:Request):AbstractResponse {
        if (!CmsAccess.can("media")) {
            return CmsController.forbidden(request);
        }
        var image = MediaAsset.query.select(["filename"])
            .where("id", PositiveInt.route(request, "id"))
            .where("trashed_epoch", ">", 0)
            .limit(1)
            .first();
        var disk = Storage.disk("media");
        var path = image == null ? "" : MediaCatalog.trashPath(image.filename);
        if (image == null || !disk.fileExists(path)) {
            abort(404);
        }
        return disk.response(path, image.filename, ["Cache-Control" => "private, no-store"]);
    }

    static function change(request:Request, action:Int->Void, done:String,
            returnUrl:String):AbstractResponse {
        if (!CmsAccess.can("media")) {
            return CmsController.forbidden(request);
        }
        try {
            action(PositiveInt.route(request, "id"));
            return ResponseBuilder.asRedirect(done, 303);
        } catch (error:Dynamic) {
            return index(request, Std.string(error), 422, returnUrl);
        }
    }
}
