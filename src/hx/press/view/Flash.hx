package hx.press.view;

import haxe.ds.StringMap;
import hx.well.http.Request;
import hx.well.http.RequestStatic;

/**
    Values kept in the session for the next rendered page, such as
    validation errors and submitted input. A request reads them once; later
    flashes in the same request merge by key. Requests without a session,
    like public pages, keep nothing. It has no dependency on the renderer,
    so native hosts and plugins of every target can use it.
**/
class Flash {
    static inline final SESSION_KEY = "hx.press.view.flash";
    static inline final CONSUMED = "hx.press.view.flashed";

    public static function put(key:String, value:Dynamic):Void {
        var request = RequestStatic.request();
        if (request == null || request.session == null) {
            return;
        }
        var data:Map<String, Dynamic> = request.session.get(SESSION_KEY,
            new Map<String, Dynamic>());
        data.set(key, value);
        request.session.put(SESSION_KEY, data);
    }

    /** The flashed value of a key; the first read takes all values out of the session. **/
    public static function get(request:Null<Request>, key:String):Dynamic {
        return consume(request).get(key);
    }

    /** Takes this request's flashed values out of the session, once; a rendered page always does. **/
    public static function consume(request:Null<Request>):Map<String, Dynamic> {
        if (request == null) {
            return [];
        }
        var consumed:Null<Map<String, Dynamic>> = request.getAttribute(CONSUMED, null);
        if (consumed != null) {
            return consumed;
        }
        var data:Map<String, Dynamic> = [];
        if (request.session != null) {
            var stored:Dynamic = request.session.get(SESSION_KEY);
            if (stored != null && Std.isOfType(stored, StringMap)) {
                data = cast stored;
                request.session.forget(SESSION_KEY);
            }
        }
        request.setAttribute(CONSUMED, data);
        return data;
    }
}
