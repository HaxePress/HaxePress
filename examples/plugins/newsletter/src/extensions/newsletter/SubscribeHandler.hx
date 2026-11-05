package extensions.newsletter;

import hx.press.i18n.I18n;
import hx.press.ContentCache;
import hx.well.handler.AbstractHandler;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.ResponseBuilder;
import hx.well.validator.ValidatorRule;
import hx.well.http.RequestStatic.request;
import hx.press.validation.ValidationResponder;

class SubscribeHandler extends AbstractHandler implements ValidationResponder {
    public override function validate():Bool {
        return request().validate(["email" => [Required, String, Email, Max(254)]]);
    }

    public function validationFailed(request:Request):AbstractResponse {
        var error = I18n.t("Enter a valid email address.", null, "plugin-newsletter");
        return ResponseBuilder.asJson({error: error}, 422);
    }

    public function execute(request:Request):AbstractResponse {
        var values = request.only("email");
        var submittedEmail:String = values.get("email");
        var email = StringTools.trim(submittedEmail).toLowerCase();
        Subscriber.query.upsert(["email" => email, "created_at" => Date.now().toString()],
            ["email"], ["email"]);
        ContentCache.changed("subscribers");
        var message = I18n.t("Your subscription has been saved.", null, "plugin-newsletter");
        return ResponseBuilder.asJson({message: message});
    }
}
