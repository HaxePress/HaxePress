package hx.press.http;

import haxe.http.HttpMethod;
import hx.well.route.RouteElement;
#if (target.threaded)
import sys.thread.Mutex;
#end

/**
    Smaller request body limits for individual routes, such as the chunks
    of a resumable upload. A route declares its limit in bytes with the
    `cms.bodyLimit` attribute; routes of plugins are registered when the
    plugin starts and removed when it stops. The server reads the limit
    before it reads a request body.
**/
class BodyLimits {
    public static inline final ATTRIBUTE = "cms.bodyLimit";

    /** Replaced on every change, so requests read it without a lock. **/
    static var routes:Array<RouteElement> = [];

    #if (target.threaded)
    static final lock = new Mutex();
    #end

    /** Keeps a route's declared body limit; routes without one are ignored. **/
    public static function register(route:RouteElement):Void {
        if (route.getAttribute(ATTRIBUTE, -1) < 0) {
            return;
        }
        update(current -> current.contains(route) ? current : current.concat([route]));
    }

    public static function unregister(route:RouteElement):Void {
        update(current -> current.filter(entry -> entry != route));
    }

    /** The limit of the first registered route matching the request, or `-1`. **/
    public static function limit(method:String, path:String):Int {
        var registered = routes;
        if (registered.length == 0) {
            return -1;
        }
        var query = path.indexOf("?");
        var target = query < 0 ? path : path.substr(0, query);
        if (target.length > 1 && StringTools.endsWith(target, "/")) {
            target = target.substr(0, target.length - 1);
        }
        var requested:HttpMethod = cast method.toUpperCase();
        for (route in registered) {
            if (route.getMethods().contains(requested) && route.matches(target) != null) {
                return route.getAttribute(ATTRIBUTE, -1);
            }
        }
        return -1;
    }

    static function update(change:Array<RouteElement>->Array<RouteElement>):Void {
        #if (target.threaded)
        lock.acquire();
        #end
        routes = change(routes);
        #if (target.threaded)
        lock.release();
        #end
    }
}
