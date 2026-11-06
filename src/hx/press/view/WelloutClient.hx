package hx.press.view;

import haxe.Resource;
import haxe.crypto.Md5;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.ResponseBuilder;
import hx.well.http.StringResponse;

/**
    Serves the Wellout client runtime (`client/wellout.js` of the wellout
    library), embedded at compile time. Its URL carries a content hash, so
    browsers may cache it for a year.
**/
class WelloutClient {
    static final source:String = load();
    static final version:String = Md5.encode(source).substr(0, 12);

    public static function url():String {
        return '/_wellout/runtime-${version}.js';
    }

    public static function serve(request:Request):AbstractResponse {
        var file = request.route("file");
        if (file != 'runtime-${version}.js') {
            return ResponseBuilder.asRedirect(url(), 302);
        }
        var response = new StringResponse(source, 200);
        response.header("Content-Type", "text/javascript; charset=utf-8");
        response.header("Cache-Control", "public, max-age=31536000, immutable");
        return response;
    }

    static function load():String {
        ViewEmbed.client();
        var text = Resource.getString("wellout.client");
        return text == null ? "" : text;
    }
}
