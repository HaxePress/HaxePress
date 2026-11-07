package hx.press.validation;

import hx.well.http.Request;

/** Checkbox fields: "1" when ticked and "0" when sent unticked. **/
class Flag {
    public static function valid(value:Dynamic):Bool {
        return Std.isOfType(value, String) && (value == "0" || value == "1");
    }

    /** Whether the request's checkbox `key` is ticked; an absent box is not. **/
    public static function input(request:Request, key:String):Bool {
        var value:Dynamic = request.input(key, "0");
        return Std.isOfType(value, String) && value == "1";
    }
}
