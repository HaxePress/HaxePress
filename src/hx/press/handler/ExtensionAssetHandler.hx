package hx.press.handler;

import hx.well.handler.PublicHandler;
import hx.press.packages.PackageData;
import hx.press.packages.PackageManifest;
import hx.press.CmsAccess;
import hx.well.facades.Storage;
import hx.well.storage.InvalidStoragePath;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.ResponseStatic.abort;

class ExtensionAssetHandler extends PublicHandler {
    var preview:Bool;

    public function new(preview:Bool = false) {
        super();
        this.preview = preview;
    }

    public override function execute(request:Request):AbstractResponse {
        if (preview && !CmsAccess.can("extensions")) {
            abort(403);
        }
        var item = PackageData.one(request.route("id"));
        var asset = request.route("asset");
        if (item == null
            || (!preview && item.enabled != 1)
            || item.directory != request.route("generation")
            || !PackageManifest.safePath(asset)
            || !~/\.(js|mjs|css|json|png|jpg|jpeg|gif|svg|webp|avif|ttf|woff|woff2|otf|map)$/.match(asset)) {
            abort(404);
        }
        var disk = Storage.disk("extensions");
        var path = "installed/" + item.directory + "/public/" + asset;
        var headers = [
            "Cache-Control" => preview ? "private, no-store" : "public, max-age=31536000, immutable"
        ];
        try {
            if (!disk.fileExists(path)) {
                abort(404);
            }
            return disk.response(path, null, headers);
        } catch (_:InvalidStoragePath) {
            abort(403);
            return null;
        }
    }
}
