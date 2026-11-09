package hx.press.view;

import haxe.Json;
import hx.press.ContentCache;
#if (target.threaded)
import sys.thread.Mutex;
#else
import hx.well.thread.FakeMutex as Mutex;
#end
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
class IslandCatalogues {
    static final versions:Map<String, String> = [];
    static final bodies:Map<String, String> = [];
    static final lock = new Mutex();

    /** The revision of the site's translations the cached bodies were made from. **/
    static var revision = "";

    public static function url():String {
        var locale = I18n.locale();
        return '/_translations/${locale}-${version(locale)}.json';
    }

    static function version(locale:String):String {
        var current = ContentCache.revision("translations");
        lock.acquire();
        if (revision != current) {
            versions.clear();
            bodies.clear();
            revision = current;
        }
        var known = versions.get(locale);
        lock.release();
        if (known != null) {
            return known;
        }
        var body = Json.stringify(ViewData.plain(I18n.coreMessages(locale)));
        var digest = Md5.encode(body).substr(0, 12);
        lock.acquire();
        if (revision == current) {
            bodies.set(locale, body);
            versions.set(locale, digest);
        }
        lock.release();
        return digest;
    }

    static function body(locale:String):String {
        lock.acquire();
        var known = bodies.get(locale);
        lock.release();
        return known ?? Json.stringify(ViewData.plain(I18n.coreMessages(locale)));
    }

    public static function serve(request:Request):AbstractResponse {
        var file = request.route("file");
        var pattern = ~/^([a-z]{2,3}(?:-[A-Za-z0-9]{2,8})*)-([0-9a-f]{12})\.json(?![\s\S])/;
        if (!pattern.match(file) || !I18n.known(pattern.matched(1))) {
            return ResponseBuilder.asJson({error: "Unknown catalogue"}, 404);
        }
        var locale = pattern.matched(1);
        var current = version(locale);
        if (pattern.matched(2) != current) {
            return ResponseBuilder.asRedirect('/_translations/${locale}-${current}.json', 302);
        }
        var response = new StringResponse(body(locale), 200);
        response.header("Content-Type", "application/json; charset=utf-8");
        response.header("Cache-Control", "public, max-age=31536000, immutable");
        return response;
    }
}
