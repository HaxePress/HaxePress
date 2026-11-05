package hx.press.handler;

import hx.press.SiteController;
import hx.press.content.ContentTypes;
import hx.well.handler.PublicHandler;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.ResponseBuilder;

/** Native routes, including plugin routes, win; stored collection paths resolve at runtime. */
class SitePublicHandler extends PublicHandler {
    public override function execute(request:Request):AbstractResponse {
        var response = collection(request, request.path);
        return response == null ? super.execute(request) : response;
    }

    public static function collection(request:Request, path:String):Null<AbstractResponse> {
        var pattern = ~/^\/([a-z0-9]+(?:-[a-z0-9]+)*)(?:\/([a-z0-9]+(?:-[a-z0-9]+)*))?\/?$/;
        if (!pattern.match(path)) {
            return null;
        }
        var prefix = pattern.matched(1);
        var slug = pattern.matched(2) ?? "";
        var type = ContentTypes.byPath(prefix);
        if (type == null) {
            return null;
        }
        if (request.method != "GET" && request.method != "HEAD") {
            return ResponseBuilder.asString("Method not allowed.", 405)
                .header("Allow", "GET, HEAD");
        }
        if (type.publicBase != "/" + prefix) {
            var query = [
                for (key => value in request.queries)
                    StringTools.urlEncode(key) + "=" + StringTools.urlEncode(value)
            ];
            var previewBase:String = request.getAttribute("hx.press.preview.base", "");
            var location = previewBase + type.publicBase + (slug == "" ? "" : "/" + slug);
            if (query.length > 0) {
                location += "?" + query.join("&");
            }
            return ResponseBuilder.asRedirect(location, 301);
        }
        if (slug == "") {
            return type.hasArchive ? SiteController.index(request,
                type.key) : SiteController.notFound(request);
        }
        return SiteController.content(request, type.key, slug);
    }
}
