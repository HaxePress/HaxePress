package hx.press.handler.admin.auth;

import hx.press.i18n.I18n;
import hx.press.handler.admin.account.ChangeAdminLocaleHandler;
import haxe.crypto.Sha256;
import haxe.ds.StringMap;
import hx.well.handler.AbstractHandler;
import hx.well.http.Request;
import hx.well.http.AbstractResponse;
import hx.well.http.ResponseBuilder;
import hx.well.http.RequestStatic.auth;
import hx.well.http.RequestStatic.request;
import hx.well.validator.ValidatorRule;
import hx.well.facades.Hash;
import hx.press.model.Admin;
import hx.press.model.LoginAttempt;
import hx.press.AdminController;
import hx.press.CategoryData;
import hx.well.thread.MutexPool;
import hx.press.access.Roles;

class LoginHandler extends AbstractHandler {
    static final attemptLocks = new MutexPool();

    public override function validate():Bool {
        return request().validate([
            "email" => [Required, String, Email, Max(254)],
            "password" => [Required, String, Min(1), Max(72)]
        ]);
    }

    public function execute(request:Request):AbstractResponse {
        var credentials:StringMap<Dynamic> = request.only("email", "password");
        var email = CategoryData.key(credentials.get("email"));
        credentials.set("email", email);
        var password:String = credentials.get("password");
        var key = Sha256.encode('login:${request.ip}');
        var now = Date.now().getTime() / 1000;
        var allowed = true;
        attemptLocks.acquire(key);
        try {
            var attempt = LoginAttempt.query.find(key);
            if (attempt != null && attempt.expires_at > now && attempt.attempts >= 5) {
                allowed = false;
            } else {
                var expired = attempt == null || attempt.expires_at < now;
                var attemptCount = expired ? 1 : attempt.attempts + 1;
                var expiresAt = expired ? now + 900 : attempt.expires_at;
                LoginAttempt.query.upsert(["key" => key, "attempts" => attemptCount, "expires_at" => expiresAt],
                    ["key"], ["attempts", "expires_at"]);
            }
            attemptLocks.release(key);
        } catch (error:Dynamic) {
            attemptLocks.release(key);
            throw error;
        }
        if (!allowed) {
            return AdminController.loginForm(request,
                "Too many attempts. Please try again in 15 minutes.", 429);
        }
        var adminAuth = auth("admin");
        var candidate = Admin.query.select(["active", "role"]).where("email", email).first();
        if (candidate == null) {
            Hash.check(password, Admin.query.select(["password"]).limit(1).first().password);
        }
        if (candidate == null
            || candidate.active != 1
            || !Roles.exists(candidate.role)
            || !adminAuth.attempt(credentials)) {
            return AdminController.loginForm(request, "The email or password is incorrect.", 401);
        }
        LoginAttempt.query.where("key", key).delete();
        var admin:Admin = adminAuth.user();
        request.session.put("admin_name", admin.name);
        request.session.put("auth_version", admin.password);
        // The language chosen on the sign-in page becomes the member's own.
        var chosen = request.cookie(ChangeAdminLocaleHandler.COOKIE, "");
        if (admin.ui_language == "" && I18n.adminLocale(chosen)) {
            admin.update(["ui_language" => chosen]);
        }
        return ResponseBuilder.asRedirect("/admin", 303);
    }
}
