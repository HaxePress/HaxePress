package plugins;

import haxe.Exception;
import haxe.Json;
import hx.press.model.Subscriber;
import hx.press.validation.ValidationResponder;
import hx.well.handler.AbstractHandler;
import hx.well.facades.Cache;
import hx.well.http.Request;
import hx.well.http.RequestStatic;

/** Verify the host-shared validation contract on real CPPIA and PHP handlers. */
class PluginValidationChecks {
    static function check(value:Bool, message:String):Void {
        if (!value) {
            throw new Exception(message);
        }
    }

    public static function run(handler:AbstractHandler):Void {
        var cacheKey = "native-validation-İçerik-😊";
        var message = "Önbellekteki içerik 😊";
        Cache.store().put(cacheKey, {message: message}, 60);
        var restored:Dynamic = Cache.store().get(cacheKey);
        check(restored != null && restored.message == message,
            "Native cache truncated a UTF-8 key or serialized value");
        Cache.store().forget(cacheKey);
        var current = new Request();
        current.method = "POST";
        current.path = "/subscribe?email=invalid-email";
        RequestStatic.set(current);
        check(!handler.validate(), "Native plugin did not reject an invalid email");
        check(Std.isOfType(handler, ValidationResponder),
            "Native plugin did not share the host validation response interface");
        var responder:ValidationResponder = cast handler;
        var rejected = responder.validationFailed(current).toResponse();
        check(rejected.statusCode == 422 && Json.parse(rejected.toString()).error != null,
            "Native plugin lost its JSON validation response");

        var email = 'native-validation-${Std.random(1000000000)}@example.test';
        current.path = '/subscribe?email=${StringTools.urlEncode(email)}';
        check(handler.validate(), "Native plugin rejected a valid email");
        var accepted = handler.execute(current).toResponse();
        check(Json.parse(accepted.toString()).message != null,
            "Native validated subscription did not execute");
        var originalDate = "2000-01-01 00:00:00";
        Subscriber.query.where("email", email).update(["created_at" => originalDate]);
        handler.execute(current);
        check(Subscriber.query.where("email", email).count() == 1,
            "Native validation changed subscription deduplication");
        var retained = Subscriber.query.select(["created_at"]).where("email", email).first();
        check(Std.string(retained.created_at) == originalDate,
            "A duplicate subscription replaced its original creation date");
        Subscriber.query.where("email", email).delete();
        RequestStatic.reset();
        Sys.println("PASS Native plugin handler: validate, shared failure interface, JSON errors and deduplicated writes");
    }
}
