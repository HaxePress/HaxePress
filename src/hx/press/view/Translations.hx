package hx.press.view;

import haxe.Json;
import haxe.crypto.Md5;
import hx.press.i18n.I18n;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.ResponseBuilder;
import hx.well.http.StringResponse;

/**
    The CMS translation catalogue for client islands, one immutable file
    per locale and catalogue version. Islands fetch it once and the browser
    caches it, instead of every page carrying the catalogue.
**/
class Translations {
    static final versions:Map<String, String> = [];
    static final bodies:Map<String, String> = [];

    public static function url():String {
        var locale = I18n.locale();
        return '/_translations/${locale}-${version(locale)}.json';
    }

    static function version(locale:String):String {
        var known = versions.get(locale);
        if (known != null) {
            return known;
        }
        var body = Json.stringify(ViewData.plain(I18n.coreMessages(locale)));
        var digest = Md5.encode(body).substr(0, 12);
        bodies.set(locale, body);
        versions.set(locale, digest);
        return digest;
    }

    public static function serve(request:Request):AbstractResponse {
        var file = request.route("file");
        var pattern = ~/^([a-z]{2})-([0-9a-f]{12})\.json$/;
        if (!pattern.match(file) || !I18n.supported(pattern.matched(1))) {
            return ResponseBuilder.asJson({error: "Unknown catalogue"}, 404);
        }
        var locale = pattern.matched(1);
        var current = version(locale);
        if (pattern.matched(2) != current) {
            return ResponseBuilder.asRedirect('/_translations/${locale}-${current}.json', 302);
        }
        var response = new StringResponse(bodies.get(locale), 200);
        response.header("Content-Type", "application/json; charset=utf-8");
        response.header("Cache-Control", "public, max-age=31536000, immutable");
        return response;
    }
}
