package plugins;

import haxe.Exception;
import haxe.Json;
import hx.well.facades.Inertia;
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
            Inertia.flash("notice", "first");
            Inertia.flash("notice", "replacement");
            Inertia.flash(values);
            var flashed = Inertia.getFlashed(current);
            check(flashed.get("notice") == "replacement"
                && flashed.get("count") == 0
                && flashed.get("enabled") == false
                && flashed.get("label") == "İçerik",
                "Native Inertia flash failed to merge calls or retain values");
            check(!Inertia.getFlashed(current).keys().hasNext(),
                "Native Inertia flash was consumed more than once");
            current.session = null;
            Inertia.flash("notice", "ignored");
            check(current.session == null && !Inertia.getFlashed(current).keys().hasNext(),
                "Native Inertia flash created a public session");
            RequestStatic.set(previous);
        } catch (error:Dynamic) {
            RequestStatic.set(previous);
            throw error;
        }
        Sys.println("PASS Native APIs: map-to-object values, merged/single-use Inertia flash and session-free public calls");
    }
}
