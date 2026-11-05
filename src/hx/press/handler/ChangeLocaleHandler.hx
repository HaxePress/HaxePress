package hx.press.handler;

import hx.press.i18n.I18n;
import hx.press.validation.ValidationResponder;
import hx.well.facades.Environment;
import hx.well.handler.AbstractHandler;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.RequestStatic.request;
import hx.well.http.ResponseBuilder;
import hx.well.http.ResponseStatic;
import hx.well.validator.ValidatorRule;

class ChangeLocaleHandler extends AbstractHandler implements ValidationResponder {
    public override function validate():Bool {
        var current = request();

        return
            current.validate(["locale" => [Required, String, Max(20)], "return_to" => [String, Max(2000)]]);
    }

    public function validationFailed(request:Request):AbstractResponse {
        return ResponseBuilder.asJson({error: I18n.t("Choose a supported language.")}, 422);
    }

    public function execute(request:Request):AbstractResponse {
        var selected = request.input("locale", "");
        if (!I18n.supported(selected)) {
            return ResponseBuilder.asJson({error: I18n.t("Choose a supported language.")}, 422);
        }
        var returnTo = request.input("return_to", "/");
        if (!StringTools.startsWith(returnTo, "/")
            || StringTools.startsWith(returnTo, "//")
            || returnTo.indexOf("\\") >= 0
            || ~/[\x00-\x20]/.match(returnTo)) {
            returnTo = "/";
        }
        ResponseStatic.get()
            .cookie("cms_locale", selected)
            .path("/")
            .httpOnly(true)
            .sameSite("Lax")
            .secure(Environment.env("APP_ENV", "production") != "development")
            .maxAge(31536000);
        return ResponseBuilder.asRedirect(returnTo, 303);
    }
}
