package hx.press.handler.admin.account;

import hx.press.CmsAccess;
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

using StringTools;

/**
    Changes the administration language. A signed-in member keeps it on
    their account; the sign-in page remembers it in a cookie.
**/
class ChangeAdminLocaleHandler extends AbstractHandler implements ValidationResponder {
    public static inline var COOKIE = "cms_admin_locale";

    public override function validate():Bool {
        var current = request();
        return
            current.validate(["locale" => [Required, String, Max(35)], "return_to" => [String, Max(2000)]]);
    }

    public function validationFailed(request:Request):AbstractResponse {
        return ResponseBuilder.asJson({error: I18n.t("Choose a supported language.")}, 422);
    }

    public function execute(request:Request):AbstractResponse {
        var selected = request.input("locale", "");
        if (!I18n.adminLocale(selected)) {
            return ResponseBuilder.asJson({error: I18n.t("Choose a supported language.")}, 422);
        }
        var returnTo = request.input("return_to", "/admin");
        var unsafe = ~/[\x00-\x20]/;
        if (!(returnTo == "/admin" || returnTo.startsWith("/admin/")
            || returnTo.startsWith("/admin?"))
            || returnTo.indexOf("\\") >= 0
            || unsafe.match(returnTo)) {
            returnTo = "/admin";
        }
        var admin = CmsAccess.current();
        if (admin != null && admin.ui_language != selected) {
            admin.update(["ui_language" => selected]);
        }
        ResponseStatic.get()
            .cookie(COOKIE, selected)
            .path("/admin")
            .httpOnly(true)
            .sameSite("Lax")
            .secure(Environment.env("APP_ENV", "production") != "development")
            .maxAge(31536000);
        return ResponseBuilder.asRedirect(returnTo, 303);
    }
}
