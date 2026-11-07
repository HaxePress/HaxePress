package hx.press.validation;

import hx.well.http.Request;
import hx.well.http.ResponseStatic.abort;

/**
    Positive whole numbers written as plain digits, such as record IDs,
    versions and limits. `Std.parseInt` is no substitute: it accepts signs,
    spaces and hexadecimal, and on the JVM it throws for a number that does
    not fit in an Int, which made a long ID in a URL a server error.
**/
class PositiveInt {
    /** The largest Int on every target. **/
    public static inline final MAX = 2147483647;

    // MAX has ten digits; longer text cannot fit, so it is not read further.
    static inline final MAX_DIGITS = 10;

    /** The number `text` names, from 1 to `max`, or null for anything else. **/
    public static function parse(text:Null<String>, max:Int = MAX):Null<Int> {
        if (text == null || text.length == 0 || text.length > MAX_DIGITS) {
            return null;
        }
        if (StringTools.fastCodeAt(text, 0) == "0".code) {
            return null;
        }
        // A Float holds every ten-digit number exactly, so the range check cannot overflow.
        var value = 0.0;
        for (index in 0...text.length) {
            var code = StringTools.fastCodeAt(text, index);
            if (code < "0".code || code > "9".code) {
                return null;
            }
            value = value * 10 + (code - "0".code);
        }
        return value <= max ? Std.int(value) : null;
    }

    /** The record ID in the route parameter `name`; any other value answers 404. **/
    public static function route(request:Request, name:String):Int {
        var id = parse(request.route(name));
        if (id == null) {
            abort(404);
        }
        return id;
    }
}
