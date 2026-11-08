package extensions.viewcount;

import hx.press.content.ContentViews;
import hx.well.http.Request;
import hx.well.http.Response;

/**
    What View Count counts as a view. A plugin that counts visits
    differently keeps its own rules; the application only tells it which
    published item a page shows and whether a member is signed in.
**/
class ViewRules {
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

    /**
        `{id, type}` of the published content item a visitor saw with this
        response, or null. Only a successful GET of a public page counts, not
        a HEAD request, a preview or other page of the administration, a
        signed-in member's browser, a crawler or a speculative load.
    **/
    public static function counted(request:Request, response:Null<Response>):Dynamic {
        var shown:Dynamic = ContentViews.content(request);
        if (shown == null || response == null || request.method != "GET") {
            return null;
        }
        var status:Null<Int> = response.statusCode;
        if (status != null && status != 200) {
            return null;
        }
        var path = request.path;
        if (path == "/admin" || StringTools.startsWith(path, "/admin/")) {
            return null;
        }
        if (ContentViews.member(request) || !fromBrowser(request)) {
            return null;
        }
        return shown;
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
