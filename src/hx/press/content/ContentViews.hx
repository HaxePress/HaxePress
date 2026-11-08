package hx.press.content;

import hx.well.http.Request;
import hx.well.http.Response;

/**
    What a request tells plugins about visits to published content.

    A public page that shows a published content item records it while it
    renders, and the `site.shared` hook receives it as `content`. After the
    response has been sent, the application counts the view if `counted`
    accepts it, by content item and `country`, and gives the counts to
    plugins once a minute with the `content.viewed` hook (`ContentViewBuffer`).
    Plugins with their own middleware can use the same functions.
**/
class ContentViews {
    /** `{id, type}` of the published content item a page shows. **/
    public static inline final CONTENT = "cms.content";

    /**
        The visitor's country as two uppercase letters, set only by a plugin
        that trusts the connection's proxy, such as the bundled Cloudflare
        plugin. Absent when the country is unknown.
    **/
    public static inline final COUNTRY = "cms.visitor.country";

    /** The value plugins use when no trusted country is known. **/
    public static inline final UNKNOWN_COUNTRY = "UNKNOWN";

    /**
        Set for the whole site while a member is signed in, because public
        pages run without the administration's session. It only tells
        counters to leave the visit out; it grants nothing.
    **/
    public static inline final MEMBER_COOKIE = "cms_member";

    /** Parts of the User-Agent of crawlers, link previews and other automated clients. **/
    static final automatedAgents = [
        "bot",
        "crawl",
        "spider",
        "slurp",
        "preview",
        "fetch",
        "monitor",
        "headless",
        "lighthouse",
        "pingdom",
        "facebookexternalhit",
        "embedly",
        "whatsapp",
        "phantomjs",
        "puppeteer",
        "playwright",
        "selenium",
        "scrapy",
        "python",
        "curl",
        "wget",
        "httpclient",
        "feed",
        "archiver"
    ];

    /** Headers browsers send when they load a page speculatively, before anyone sees it. **/
    static final speculativeHeaders = ["Sec-Purpose", "Purpose", "X-Purpose", "X-Moz"];

    /** Records that the page rendering for `request` shows the published item `id`. **/
    public static function shown(request:Request, id:Int, type:String):Void {
        request.setAttribute(CONTENT, {id: id, type: type});
    }

    /** `{id, type}` of the published item the request's page shows, or null. **/
    public static function content(request:Null<Request>):Dynamic {
        return request == null ? null : request.getAttribute(CONTENT, null);
    }

    /**
        The ID of the published content item a visitor saw with this
        response, or 0. Only a successful GET of a public page counts, not a
        HEAD request, a preview or other page of the administration, a
        signed-in member's browser, a crawler or a speculative load.
    **/
    public static function counted(request:Request, response:Null<Response>):Int {
        var shown:Dynamic = content(request);
        if (shown == null || response == null || request.method != "GET") {
            return 0;
        }
        var status:Null<Int> = response.statusCode;
        if (status != null && status != 200) {
            return 0;
        }
        var path = request.path;
        if (path == "/admin" || StringTools.startsWith(path, "/admin/")) {
            return 0;
        }
        if (request.cookie(MEMBER_COOKIE) != null || !fromBrowser(request)) {
            return 0;
        }
        var id:Int = shown.id;
        return id;
    }

    /** The trusted country of the visitor, or `UNKNOWN_COUNTRY`. **/
    public static function country(request:Request):String {
        var value:Dynamic = request.getAttribute(COUNTRY, null);
        if (!Std.isOfType(value, String)) {
            return UNKNOWN_COUNTRY;
        }
        var code:String = value;
        return validCountry(code) ? code : UNKNOWN_COUNTRY;
    }

    /** Whether `code` is two uppercase ASCII letters. **/
    public static function validCountry(code:Null<String>):Bool {
        if (code == null || code.length != 2) {
            return false;
        }
        for (index in 0...2) {
            var letter = StringTools.fastCodeAt(code, index);
            if (letter < "A".code || letter > "Z".code) {
                return false;
            }
        }
        return true;
    }

    static function fromBrowser(request:Request):Bool {
        var agent = request.header("User-Agent");
        if (agent == null || !StringTools.startsWith(agent, "Mozilla/")) {
            return false;
        }
        for (name in speculativeHeaders) {
            if (request.header(name) != null) {
                return false;
            }
        }
        var normalized = agent.toLowerCase();
        for (marker in automatedAgents) {
            if (normalized.indexOf(marker) >= 0) {
                return false;
            }
        }
        return true;
    }
}
