package hx.press.themes;

import hx.press.CmsAccess;
import hx.press.CmsController;
import hx.press.MediaCatalog;
import hx.press.Pagination;
import hx.press.SiteController;
import hx.press.content.ContentTypes;
import hx.press.model.ContentType;
import hx.press.model.ThemeDesign;
import hx.press.model.MediaAsset;
import hx.press.media.MediaReferences;
import hx.press.themes.ThemeAiAccess.ThemeAiActor;
import hx.well.facades.Storage;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.ResponseBuilder;

class ThemeAiController {
    public static function connection(request:Request):AbstractResponse {
        if (!CmsAccess.can("extensions")) {
            return CmsController.forbidden(request);
        }
        var id = request.route("id");
        if (!ThemeDesign.query.where("id", id).exists()) {
            return SiteController.notFound(request);
        }
        var admin = CmsAccess.current();
        var issued:Null<{token:String, expires:Float}> = null;
        if (request.method == "POST") {
            issued = ThemeAiAccess.create(id, admin);
        } else if (request.method == "DELETE") {
            ThemeAiAccess.revoke(id, admin.id);
        }
        var expires = issued == null ? ThemeAiAccess.expires(id, admin.id) : issued.expires;
        return ResponseBuilder.asJson({
            token: issued == null ? null : issued.token,
            expires: expires,
            active: expires > Date.now().getTime(),
            permissions: ThemeAiPermissions.forAdmin(id, admin.id, CmsAccess.can("media")),
            mediaAllowed: CmsAccess.can("media"),
            presence: ThemeCollaboration.presence(id),
            browserPath: "/admin/themes/" + id + "/ai/ws",
            mcpPath: "/mcp/themes/" + id,
            websocketPath: "/mcp/themes/" + id + "/ws",
            hosted: ThemeMcpHost.available()
        }).header("Cache-Control", "private, no-store");
    }

    public static function status(request:Request):AbstractResponse {
        if (!CmsAccess.can("extensions")) {
            return CmsController.forbidden(request);
        }
        var record = ThemeDesignData.status(request.route("id"));
        if (record == null) {
            return SiteController.notFound(request);
        }
        return ResponseBuilder.asJson({
            version: record.version,
            publishedVersion: record.published_version
        }).header("Cache-Control", "private, no-store");
    }

    public static function snapshot(request:Request):AbstractResponse {
        if (!CmsAccess.can("extensions")) {
            return CmsController.forbidden(request);
        }
        return read(request);
    }

    public static function read(request:Request):AbstractResponse {
        var snapshot = ThemeDesignData.snapshot(request.route("id"));
        if (snapshot == null) {
            return ResponseBuilder.asJson({error: "This theme is no longer available."}, 404);
        }
        var collections = ContentTypes.available(ContentType.query.select(["key", "name"]))
            .where("public_visible", 1)
            .orderBy("position")
            .orderBy("key")
            .limit(64)
            .get()
            .map(model -> model.toObject());
        return ResponseBuilder.asJson({
            theme: snapshot,
            collections: collections,
            mediaRules: ThemeAssets.rules(request.route("id"))
        }).header("Cache-Control", "private, no-store");
    }

    public static function media(request:Request):AbstractResponse {
        var actor:ThemeAiActor = request.getAttribute(ThemeAiAccess.ACTOR);
        if (actor == null || !actor.mediaAllowed) {
            return ResponseBuilder.asJson({error: "This account cannot browse the media library."},
                403);
        }
        var query = StringTools.trim(request.query("q", "")).substr(0, 80);
        var cursor = Pagination.cursor(request);
        var page = MediaCatalog.page(query, cursor);
        var count = MediaCatalog.count(query);
        var links = Pagination.links(request.path, ["q" => query], page, cursor, count,
            item -> item.id, item -> null);
        var disk = Storage.disk("media");
        var items = page.items.map(item -> {
            var data:Dynamic = Reflect.copy(item);
            data.url = disk.url(item.filename);
            return data;
        });
        return ResponseBuilder.asJson({items: items, pagination: links});
    }

    public static function collection(request:Request):AbstractResponse {
        var type = ContentTypes.find(request.route("key"));
        if (type == null || !type.publicVisible) {
            return
                ResponseBuilder.asJson({error: "Choose an available public content collection."},
                    404);
        }
        return ResponseBuilder.asJson({collection: ContentTypes.publicInfo(type)});
    }

    public static function image(request:Request):AbstractResponse {
        var actor:ThemeAiActor = request.getAttribute(ThemeAiAccess.ACTOR);
        if (actor == null || !actor.mediaAllowed) {
            return ResponseBuilder.asJson({error: "This account cannot browse the media library."},
                403);
        }
        var image = MediaAsset.query.select(["filename", "mime_type"])
            .where("id", Std.parseInt(request.route("media")))
            .limit(1)
            .first();
        var disk = Storage.disk("media");
        if (image == null
            || !MediaReferences.validFilename(image.filename)
            || !MediaReferences.mimeTypes.contains(image.mime_type)
            || !disk.fileExists(image.filename)
            || disk.size(image.filename) > MediaReferences.MAX_BYTES) {
            return
                ResponseBuilder.asJson({error: "Choose an available image from the media library."},
                    404);
        }
        return disk.response(image.filename, image.filename,
            ["Content-Type" => image.mime_type, "Cache-Control" => "private, no-store"]);
    }
}
