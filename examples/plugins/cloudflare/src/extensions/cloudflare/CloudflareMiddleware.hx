package extensions.cloudflare;

import hx.press.content.ContentViews;
import hx.well.http.Request;
import hx.well.http.Response;
import hx.well.middleware.AbstractMiddleware;

/**
    On connections from Cloudflare, sets the request's address to the
    visitor's address from `CF-Connecting-IP` and the `cms.visitor.country`
    attribute to the country from `CF-IPCountry`. Anyone can send these
    headers, so they are ignored on every other connection, and a value that
    is not a single IP address or a two-letter country is ignored too.
**/
class CloudflareMiddleware extends AbstractMiddleware {
    /** Whether connections from this server's loopback addresses come from Cloudflare Tunnel. **/
    public static var tunnel = false;

    public function handle(request:Request, next:Request->Null<Response>):Null<Response> {
        var forwarded = request.header("CF-Connecting-IP");
        var country = request.header("CF-IPCountry");
        if ((forwarded == null && country == null)
            || !CloudflareAddresses.fromCloudflare(request.ip, tunnel)) {
            return next(request);
        }
        var code = CloudflareCountry.normalize(country);
        if (code != null) {
            request.setAttribute(ContentViews.COUNTRY, code);
        }
        if (forwarded != null) {
            var visitor = StringTools.trim(forwarded);
            if (CloudflareAddresses.parse(visitor) != null) {
                request.ip = visitor;
            }
        }
        return next(request);
    }
}
