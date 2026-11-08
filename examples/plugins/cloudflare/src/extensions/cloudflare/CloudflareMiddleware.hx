package extensions.cloudflare;

import hx.well.http.Request;
import hx.well.http.Response;
import hx.well.middleware.AbstractMiddleware;

/**
    Sets the request's address to the visitor's address from
    `CF-Connecting-IP` when the connection comes from Cloudflare. Anyone can
    send the header, so it is ignored on every other connection, and a value
    that is not a single IP address is ignored too.
**/
class CloudflareMiddleware extends AbstractMiddleware {
    /** Whether connections from this server's loopback addresses come from Cloudflare Tunnel. **/
    public static var tunnel = false;

    public function handle(request:Request, next:Request->Null<Response>):Null<Response> {
        var forwarded = request.header("CF-Connecting-IP");
        if (forwarded != null && CloudflareAddresses.fromCloudflare(request.ip, tunnel)) {
            var visitor = StringTools.trim(forwarded);
            if (CloudflareAddresses.parse(visitor) != null) {
                request.ip = visitor;
            }
        }
        return next(request);
    }
}
