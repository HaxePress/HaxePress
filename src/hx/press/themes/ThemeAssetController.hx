package hx.press.themes;

import hx.press.CmsAccess;
import hx.press.Pagination;
import hx.press.model.ThemeAsset;
import hx.press.model.ThemeDesign;
import hx.well.facades.Storage;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.ResponseBuilder;

class ThemeAssetController {
    public static function index(request:Request):AbstractResponse {
        if (!CmsAccess.can("extensions")) {
            return ResponseBuilder.asJson({error: "Theme management access is required."}, 403);
        }
        return listing(request);
    }

    public static function listing(request:Request):AbstractResponse {
        var id = request.route("id");
        if (!ThemeDesign.query.where("id", id).exists()) {
            return ResponseBuilder.asJson({error: "This theme is no longer available."}, 404);
        }
        var search = StringTools.trim(request.query("q", "")).substr(0, 80);
        var cursor = Pagination.cursor(request);
        var page = ThemeAssets.page(id, search, cursor);
        var count = ThemeAssets.count(id, search);
        var links = Pagination.links(request.path, ["q" => search], page, cursor, count,
            item -> item.id, item -> null);
        var used = page.items.length == 0 ? new Map<String, Bool>() : ThemeAssets.used(id);
        var images = page.items.map(item -> {
            var data:Dynamic = Reflect.copy(item);
            data.url = ThemeAssets.url(id, item.filename);
            data.in_use = used.exists(data.url);
            return data;
        });
        return ResponseBuilder.asJson({images: images, pagination: links})
            .header("Cache-Control", "private, no-store");
    }

    public static function image(request:Request):AbstractResponse {
        var id = request.route("id");
        var filename = request.route("filename");
        return serve(id, filename);
    }

    public static function readForAi(request:Request):AbstractResponse {
        var id = request.route("id");
        var asset = ThemeAsset.query.select(["filename", "mime_type"])
            .where("theme_id", id)
            .where("id", Std.parseInt(request.route("asset")))
            .limit(1)
            .first();
        if (asset == null) {
            return ResponseBuilder.asJson({error: "Choose an image owned by this theme."}, 404);
        }
        return serve(id, asset.filename, true, asset.mime_type);
    }

    static function serve(id:String, filename:String, privateResponse:Bool = false,
            ?mimeType:String):AbstractResponse {
        if (!ThemeAssets.validThemeId(id)
            || !ThemeAssets.imageUrl('/theme-assets/${id}/${filename}')) {
            return ResponseBuilder.asString("Theme image not found.", 404);
        }
        if (mimeType == null) {
            var asset = ThemeAssets.find(id, filename);
            if (asset == null) {
                return ResponseBuilder.asString("Theme image not found.", 404);
            }
            mimeType = asset.mime_type;
        }
        var path = '${id}/${filename}';
        var disk = Storage.disk("theme_assets");
        if (!disk.fileExists(path)) {
            return ResponseBuilder.asString("Theme image not found.", 404);
        }
        return disk.response(path, filename, [
            "Content-Type" => mimeType,
            "Cache-Control" =>
            privateResponse ? "private, no-store" : "public, max-age=31536000, immutable",
            "X-Content-Type-Options" => "nosniff"
        ]);
    }

    public static function remove(request:Request):AbstractResponse {
        if (!CmsAccess.can("extensions")) {
            return ResponseBuilder.asJson({error: "Theme management access is required."}, 403);
        }
        try {
            ThemeAssets.remove(request.route("id"), Std.parseInt(request.route("asset")));
            return ResponseBuilder.asJson({removed: true});
        } catch (error:Dynamic) {
            return ResponseBuilder.asJson({error: Std.string(error)}, 422);
        }
    }
}
