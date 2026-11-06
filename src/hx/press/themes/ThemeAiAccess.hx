package hx.press.themes;

import haxe.crypto.Sha256;
import hx.press.ai.AdminMcpAccess;
import hx.press.ai.AdminMcpAccess.AdminMcpError;
import hx.press.themes.ThemeAiPermissions.AiPermissions;
import hx.well.facades.Cache;
import hx.well.facades.Config;
import hx.press.CmsAccess;
import hx.press.model.Admin;
import hx.press.model.ThemeDesign;
import hx.well.http.Request;
import hx.well.internal.SecureToken;
import hx.well.facades.Environment;

typedef ThemeAiActor = {
    var id:Int;
    var name:String;
    var mediaAllowed:Bool;
    var permissions:AiPermissions;
    var uploadKey:String;
}

class ThemeAiAccess {
    public static inline var ACTOR = "hx.press.theme.ai.actor";
    static inline var BROWSER_PREFIX = "cms:theme-browser:";

    public static function authenticate(request:Request):Null<ThemeAiActor> {
        var authorization = request.header("Authorization", "");
        if (request.header("Origin", "") != "") {
            return null;
        }
        var themeId = request.route("id");
        if (StringTools.startsWith(authorization, "Bearer hxb_")) {
            return authenticateToken(themeId, authorization);
        }
        var actor = AdminMcpAccess.delegated(request);
        if (actor == null) {
            return null;
        }
        // A signed-in administrator who names a missing theme needs to know which ID to use.
        if (!ThemeDesign.query.where("id", themeId).exists()) {
            throw new AdminMcpError("theme_not_found",
                "This theme does not exist or is not a builder theme. Use list_themes to find a builder theme ID.",
                404);
        }
        return forAdmin(themeId, actor.admin, actor.sessionKey);
    }

    public static function allowedOrigin(origin:String):Bool {
        if (origin == "") {
            return true;
        }
        var configured = Environment.env("APP_URL", "http://127.0.0.1:3000");
        var pattern = ~/^(https?:\/\/[^\/?#]+)/;
        if (pattern.match(configured) && pattern.matched(1) == origin) {
            return true;
        }
        return Environment.env("MCP_ALLOWED_ORIGINS", "")
            .split(",")
            .map(StringTools.trim)
            .contains(origin);
    }

    public static function authenticateToken(themeId:String,
            authorization:String):Null<ThemeAiActor> {
        if (authorization == null) {
            return null;
        }
        if (~/^Bearer hxb_[A-Za-z0-9_-]{32}$/.match(authorization)) {
            var ticket:Null<{themeId:String, sessionKey:String}> = Cache.store()
                .get('${BROWSER_PREFIX}${Sha256.encode(authorization.substr(7))}');
            if (ticket == null || ticket.themeId != themeId) {
                return null;
            }
            return authenticateBrowser(themeId, ticket.sessionKey);
        }
        return null;
    }

    public static function browserCredential(themeId:String, sessionKey:String):String {
        var token = 'hxb_${SecureToken.generate(32)}';
        var lifetime:Int = Config.get("session.lifetime");
        Cache.store().put('${BROWSER_PREFIX}${Sha256.encode(token)}', {
            themeId: themeId,
            sessionKey: sessionKey
        }, lifetime * 60);
        return 'Bearer ${token}';
    }

    public static function forgetBrowserCredential(authorization:String):Void {
        if (authorization != null && StringTools.startsWith(authorization, "Bearer hxb_")) {
            Cache.store().forget('${BROWSER_PREFIX}${Sha256.encode(authorization.substr(7))}');
        }
    }

    public static function authenticateBrowser(themeId:String,
            sessionKey:String):Null<ThemeAiActor> {
        return forAdmin(themeId, AdminMcpAccess.browser(sessionKey), sessionKey);
    }

    static function forAdmin(themeId:String, admin:Null<Admin>,
            sessionKey:String):Null<ThemeAiActor> {
        if (admin == null || !ThemeDesign.query.where("id", themeId).exists()) {
            return null;
        }
        var grants = CmsAccess.capabilities(admin.role);
        if (!grants.contains("*") && !grants.contains("extensions")) {
            return null;
        }
        var permissions = ThemeAiPermissions.forAdmin(themeId,
            admin.id, grants.contains("*") || grants.contains("media"));
        return {
            id: admin.id,
            name: admin.name,
            mediaAllowed: permissions.media,
            permissions: permissions,
            uploadKey: 'theme-mcp:${sessionKey}:${themeId}'
        };
    }
}
