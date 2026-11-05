package hx.press.themes;

import haxe.crypto.Sha256;
import hx.press.themes.ThemeAiPermissions.AiPermissions;
import hx.well.cache.FileSystemSessionCacheStore;
import hx.well.facades.Cache;
import hx.well.facades.Config;
import hx.well.session.Session;
import hx.well.session.SessionDataType;
import hx.press.CmsAccess;
import hx.press.ContentCache;
import hx.press.model.Admin;
import hx.press.model.ThemeAiConnection;
import hx.press.model.ThemeDesign;
import hx.well.http.Request;
import hx.well.internal.SecureToken;
import hx.well.facades.Environment;

typedef ThemeAiActor = {
    var id:Int;
    var name:String;
    var mediaAllowed:Bool;
    var permissions:AiPermissions;
}

class ThemeAiAccess {
    public static inline var ACTOR = "hx.press.theme.ai.actor";
    static inline var BROWSER_PREFIX = "cms:theme-browser:";

    public static inline var LIFETIME = 24 * 60 * 60 * 1000;

    public static function create(themeId:String, admin:Admin):{token:String, expires:Float} {
        var token = "hxp_" + SecureToken.generate(32);
        var expires = Date.now().getTime() + LIFETIME;
        ThemeAiConnection.query.upsert([
            "id" => SecureToken.generate(32),
            "theme_id" => themeId,
            "admin_id" => admin.id,
            "token_hash" => Sha256.encode(token),
            "auth_version" => Sha256.encode(admin.password),
            "expires_epoch" => expires
        ],
            ["theme_id", "admin_id"], ["token_hash", "auth_version", "expires_epoch"]);
        ContentCache.changed("theme-ai");
        ThemeCollaboration.revokeLlm(themeId, admin.id);
        return {token: token, expires: expires};
    }

    public static function revoke(themeId:String, adminId:Int):Void {
        ThemeAiConnection.query.where("theme_id", themeId).where("admin_id", adminId).delete();
        ContentCache.changed("theme-ai");
        ThemeCollaboration.revokeLlm(themeId, adminId);
    }

    public static function expires(themeId:String, adminId:Null<Int> = null):Float {
        var record:Null<{expires_epoch:Float}> = ContentCache.remember("theme-ai", "connection",
            [themeId, adminId], () -> {
                var query = ThemeAiConnection.query.select(["expires_epoch"])
                    .where("theme_id", themeId);
                if (adminId != null) {
                    query.where("admin_id", adminId);
                }
                var model = query.orderBy("expires_epoch", "DESC").limit(1).first();
                return model == null ? null : cast model.toObject();
            });
        return record == null ? 0 : record.expires_epoch;
    }

    public static function authenticate(request:Request):Null<ThemeAiActor> {
        var authorization = request.header("Authorization", "");
        if (request.header("Origin", "") != "") {
            return null;
        }
        return authenticateToken(request.route("id"), authorization);
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
                .get(BROWSER_PREFIX + Sha256.encode(authorization.substr(7)));
            if (ticket == null || ticket.themeId != themeId) {
                return null;
            }
            return authenticateBrowser(themeId, ticket.sessionKey);
        }
        if (!~/^Bearer hxp_[A-Za-z0-9_-]{32}$/.match(authorization)) {
            return null;
        }
        var connection = ThemeAiConnection.query.select(["admin_id", "auth_version"])
            .where("theme_id", themeId)
            .where("token_hash", Sha256.encode(authorization.substr(7)))
            .where("expires_epoch", ">", Date.now().getTime())
            .limit(1)
            .first();
        if (connection == null) {
            return null;
        }
        return actor(themeId, connection.admin_id, connection.auth_version, true);
    }

    public static function browserCredential(themeId:String, sessionKey:String):String {
        var token = "hxb_" + SecureToken.generate(32);
        var lifetime:Int = Config.get("session.lifetime");
        Cache.store().put(BROWSER_PREFIX + Sha256.encode(token), {
            themeId: themeId,
            sessionKey: sessionKey
        }, lifetime * 60);
        return "Bearer " + token;
    }

    public static function forgetBrowserCredential(authorization:String):Void {
        if (authorization != null && StringTools.startsWith(authorization, "Bearer hxb_")) {
            Cache.store().forget(BROWSER_PREFIX + Sha256.encode(authorization.substr(7)));
        }
    }

    public static function authenticateBrowser(themeId:String,
            sessionKey:String):Null<ThemeAiActor> {
        var stored:Null<Map<String, Dynamic>> = Cache.store(FileSystemSessionCacheStore)
            .get("session." + sessionKey);
        if (stored == null || !ThemeDesign.query.where("id", themeId).exists()) {
            return null;
        }
        var session = new Session();
        session.data = stored;
        var adminId:Null<Int> = session.getWithEnum(SessionDataType.AUTH_ID("admin"));
        var authVersion:String = session.get("auth_version", "");
        if (adminId == null || authVersion == "") {
            return null;
        }
        return actor(themeId, adminId, authVersion, false);
    }

    static function actor(themeId:String, adminId:Int, authVersion:String,
            hashed:Bool):Null<ThemeAiActor> {
        var admin = Admin.query.select(["id", "name", "role", "active", "password"])
            .where("id", adminId)
            .where("active", 1)
            .limit(1)
            .first();
        if (admin == null) {
            return null;
        }
        var currentVersion = hashed ? Sha256.encode(admin.password) : admin.password;
        if (currentVersion != authVersion) {
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
            permissions: permissions
        };
    }
}
