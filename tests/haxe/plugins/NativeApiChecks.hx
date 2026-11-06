package plugins;

import haxe.Exception;
import haxe.Json;
import hx.press.view.Flash;
import hx.well.http.Request;
import hx.well.http.RequestStatic;
import hx.well.session.Session;
import hx.well.tools.MapTools;

class NativeApiChecks {
    static function check(value:Bool, message:String):Void {
        if (!value) {
            throw new Exception(message);
        }
    }

    public static function run():Void {
        var values:Map<String, Dynamic> = [
            "count" => 0,
            "enabled" => false,
            "label" => "İçerik",
            "literal.key" => "retained"
        ];
        var object = MapTools.toDynamic(values);
        var decoded:Dynamic = Json.parse(Json.stringify(object));
        check(decoded.count == 0
            && decoded.enabled == false
            && decoded.label == "İçerik"
            && Reflect.field(decoded, "literal.key") == "retained",
            "Native map conversion changed field values or names");

        var previous = RequestStatic.request();
        var current = new Request();
        current.path = "/admin/account";
        current.session = new Session();
        RequestStatic.set(current);
        try {
            Flash.put("notice", "first");
            Flash.put("notice", "replacement");
            for (key => value in values) {
                Flash.put(key, value);
            }
            check(Flash.get(current, "notice") == "replacement"
                && Flash.get(current, "count") == 0
                && Flash.get(current, "enabled") == false
                && Flash.get(current, "label") == "İçerik",
                "Flash failed to merge calls or retain values");
            var next = new Request();
            next.path = "/admin/account";
            next.session = current.session;
            check(Flash.get(next, "notice") == null, "Flash was consumed more than once");
            current.session = null;
            Flash.put("notice", "ignored");
            check(current.session == null && Flash.get(new Request(), "notice") == null,
                "Flash created a public session");
            RequestStatic.set(previous);
        } catch (error:Dynamic) {
            RequestStatic.set(previous);
            throw error;
        }
        Sys.println("PASS Native APIs: map-to-object values, merged/single-use flash and session-free public calls");
    }
}
