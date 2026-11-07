package hx.press.ai;

import haxe.Exception;
import haxe.crypto.Sha256;
import hx.press.access.Roles;
import hx.press.model.Admin;
import hx.press.model.AdminMcpLink;
import hx.well.cache.FileSystemSessionCacheStore;
import hx.well.facades.Cache;
import hx.well.facades.Environment;
import hx.well.http.Request;
import hx.well.internal.SecureToken;
import hx.well.session.Session;
import hx.well.session.SessionDataType;
import hx.well.thread.MutexPool;

typedef AdminMcpActor = {
    var admin:Admin;
    var sessionId:String;
    var expires:Float;
}

/**
    The account an in-process MCP request acts as, and the session key of
    its request-only session, so staged uploads stay bound to the
    connection that made them.
**/
typedef AdminMcpGrant = {
    var admin:Admin;
    var sessionKey:String;
}

/** A pass for the preview browser: the admin, and the theme whose preview pages it may read. **/
private typedef AdminMcpCapture = {
    var adminId:Int;
    var themeId:String;
    var expires:Float;
    var remaining:Int;
}

class AdminMcpError extends Exception {
    public final reason:String;
    public final status:Int;

    public function new(reason:String, message:String, status:Int = 401) {
        super(message);
        this.reason = reason;
        this.status = status;
    }
}

/** Each endpoint selects one grant. A bearer is valid only on its own endpoint. */
class AdminMcpAccess {
    /** The header the preview browser sends its capture pass in. **/
    public static inline var TICKET_HEADER = "X-HaxePress-Admin-Request";

    /** Marks an authorized in-process MCP request; pages answer it with data. **/
    public static inline var INTERNAL = "hx.press.admin-mcp.internal";

    /** The `AdminMcpGrant` of an in-process MCP request, before it is authorized. **/
    public static inline var ACTOR = "hx.press.admin-mcp.actor";

    /** How long a new MCP link lasts, in hours: an hour, a day, a week or 30 days. **/
    public static final lifetimes = [1, 24, 168, 720];

    public static inline var DEFAULT_LIFETIME = 24;
    static inline var HISTORY = 60 * 60 * 1000;
    static inline var MAX_LINKS = 8;

    static final captures:Map<String, AdminMcpCapture> = [];
    static final mutex = new MutexPool();

    public static function validId(value:Null<String>):Bool {
        return value != null && ~/^[A-Za-z0-9_-]{32}$/.match(value);
    }

    public static function path(id:String):String {
        return '/mcp/sessions/${id}';
    }

    public static function origin():String {
        var value = Environment.env("APP_URL", "http://127.0.0.1:3000");
        var pattern = ~/^(https:\/\/(?:[A-Za-z0-9.-]+|\[[0-9a-f:]+\])(?::[0-9]{1,5})?|http:\/\/(?:127\.0\.0\.1|\[::1\]|(?:[A-Za-z0-9.-]+\.)?localhost)(?::[0-9]{1,5})?)\/?$/;
        if (!pattern.match(value)) {
            throw new AdminMcpError("invalid_origin",
                "Set APP_URL to an HTTPS origin or a loopback development URL.", 422);
        }
        return pattern.matched(1);
    }

    public static function exists(id:Null<String>):Bool {
        return validId(id) && AdminMcpLink.query.where("id", id).exists();
    }

    public static function issue(admin:Admin, profile:String,
            hours:Int = DEFAULT_LIFETIME):Dynamic {
        if (!lifetimes.contains(hours)) {
            throw new AdminMcpError("invalid_lifetime", "Choose a supported expiry.", 422);
        }
        var id = SecureToken.generate(32);
        var address = origin();
        var token = newToken();
        var now = Date.now().getTime();
        var expires = now + hours * 60 * 60 * 1000.0;
        locked(() -> {
            var active = AdminMcpLink.query.where("admin_id", admin.id)
                .where("expires_epoch", ">", now)
                .where("auth_version", Sha256.encode(admin.password))
                .count();
            if (active >= MAX_LINKS) {
                throw new AdminMcpError("connection_limit",
                    "End an MCP session before creating another.", 429);
            }
            AdminMcpLink.query.insert([
                "id" => id,
                "admin_id" => admin.id,
                "auth_version" => Sha256.encode(admin.password),
                "profile" => profile,
                "origin" => address,
                "token_hash" => Sha256.encode(token),
                "expires_epoch" => expires,
                "first_seen_epoch" => 0,
                "last_seen_epoch" => 0,
                "created_epoch" => now
            ]);
            return true;
        });
        AdminMcpSockets.changed(admin.id);
        return {
            id: id,
            profile: profile,
            url: '${address}${path(id)}',
            token: token,
            expires: expires
        };
    }

    public static function state(admin:Admin):Dynamic {
        var links = AdminMcpLink.query.select([
            "id",
            "profile",
            "origin",
            "expires_epoch",
            "first_seen_epoch",
            "last_seen_epoch"
        ])
            .where("admin_id", admin.id)
            .where("expires_epoch", ">", Date.now().getTime())
            .where("auth_version", Sha256.encode(admin.password))
            .orderBy("created_epoch")
            .orderBy("id")
            .limit(MAX_LINKS)
            .get();
        var connections = [
            for (link in links)
                {
                    id: link.id,
                    profile: link.profile,
                    url: '${link.origin}${path(link.id)}',
                    expires: link.expires_epoch,
                    firstSeenAt: seen(link.first_seen_epoch),
                    lastSeenAt: seen(link.last_seen_epoch)
                }
        ];
        // PHP answers each request in a new process, so browsers use HTTP there.
        return {sessions: connections, websocket: #if php false #else true #end};
    }

    static function seen(epoch:Float):Null<Float> {
        return epoch > 0 ? epoch : null;
    }

    public static function recordSeen(id:String):Void {
        var now = Date.now().getTime();
        var link = AdminMcpLink.query.select(["first_seen_epoch", "last_seen_epoch"])
            .where("id", id)
            .where("expires_epoch", ">", now)
            .limit(1)
            .first();
        if (link == null) {
            return;
        }
        if (link.first_seen_epoch == 0) {
            AdminMcpLink.query.where("id", id)
                .where("first_seen_epoch", 0)
                .update(["first_seen_epoch" => now, "last_seen_epoch" => now]);
        } else if (now > link.last_seen_epoch) {
            AdminMcpLink.query.where("id", id).update(["last_seen_epoch" => now]);
        }
    }

    /**
        Sets a new expiry, counted from now, for a link that no client has
        used yet. Once a client connects, its expiry stays as it is.
    **/
    public static function changeExpiry(adminId:Int, id:String, hours:Int):Void {
        if (!lifetimes.contains(hours)) {
            throw new AdminMcpError("invalid_lifetime", "Choose a supported expiry.", 422);
        }
        var now = Date.now().getTime();
        var link = validId(id) ? AdminMcpLink.query.select(["first_seen_epoch"])
            .where("id", id)
            .where("admin_id", adminId)
            .where("expires_epoch", ">", now)
            .limit(1)
            .first() : null;
        if (link == null) {
            throw new AdminMcpError("session_inactive", "This MCP session is inactive.", 404);
        }
        // Only an unused link changes, also when a client connects at this moment.
        AdminMcpLink.query.where("id", id)
            .where("first_seen_epoch", 0)
            .update(["expires_epoch" => now + hours * 60 * 60 * 1000.0]);
        if (link.first_seen_epoch != 0
            || !AdminMcpLink.query.where("id", id).where("first_seen_epoch", 0).exists()) {
            throw new AdminMcpError("session_used",
                "This MCP link is already connected; its expiry can no longer change.", 409);
        }
        AdminMcpSockets.changed(adminId);
    }

    public static function end(adminId:Int, id:String):Void {
        if (!validId(id) || !AdminMcpLink.query.where("id", id)
            .where("admin_id", adminId)
            .exists()) {
            throw new AdminMcpError("session_inactive", "This MCP session is inactive.", 404);
        }
        AdminMcpLink.query.where("id", id).where("admin_id", adminId).delete();
        AdminMcpSockets.changed(adminId);
    }

    public static function authenticate(id:String, authorization:String):AdminMcpActor {
        if (authorization == null || authorization == "") {
            throw new AdminMcpError("authorization_required",
                "Supply the bearer token for this MCP URL.");
        }
        if (!~/^Bearer hxa_[A-Za-z0-9_-]{32}$/i.match(authorization)) {
            throw invalidToken();
        }
        var link = current(id);
        if (link.token_hash != Sha256.encode(authorization.substr(7))) {
            throw invalidToken();
        }
        var admin = activeAdmin(link.admin_id);
        if (!belongsTo(link, admin)) {
            throw invalidToken();
        }
        return {admin: admin, sessionId: id, expires: link.expires_epoch};
    }

    public static function browser(sessionKey:String):Null<Admin> {
        if (!validId(sessionKey)) {
            return null;
        }
        var stored:Null<Map<String, Dynamic>> = Cache.store(FileSystemSessionCacheStore)
            .get('session.${sessionKey}');
        if (stored == null) {
            return null;
        }
        var session = new Session();
        session.data = stored;
        var id:Null<Int> = session.getWithEnum(SessionDataType.AUTH_ID("admin"));
        var admin = id == null ? null : activeAdmin(id);
        return admin != null && admin.password == session.get("auth_version", "") ? admin : null;
    }

    /** The grant of a remote MCP link's requests. **/
    public static function grant(actor:AdminMcpActor):AdminMcpGrant {
        return {
            admin: actor.admin,
            sessionKey: Sha256.encode('admin-mcp:${actor.sessionId}').substr(0, 32)
        };
    }

    /** The grant of a signed-in browser's MCP messages, or `null` once its session ends. **/
    public static function browserGrant(sessionKey:String):Null<AdminMcpGrant> {
        var admin = browser(sessionKey);
        return admin == null ? null : {admin: admin, sessionKey: sessionKey};
    }

    /**
        The account of a preview browser request: the headless browser on
        this host sends a capture pass to read one theme's preview pages and
        their assets as the admin.
    **/
    public static function delegated(request:Request):Null<AdminMcpGrant> {
        var value = request.header(TICKET_HEADER, "");
        if (!validId(value)
            || (request.ip != "127.0.0.1" && request.ip != "::ffff:127.0.0.1")
            || request.header("Forwarded") != null
            || request.header("X-Forwarded-For") != null
            || request.header("X-Real-IP") != null) {
            return null;
        }
        var capture = locked(() -> {
            var pass = captures.get(value);
            if (pass == null || pass.remaining <= 0 || pass.expires <= Date.now().getTime()) {
                return null;
            }
            pass.remaining--;
            return pass;
        });
        if (capture == null || request.method != "GET"
            || !capturable(request.path, capture.themeId)) {
            return null;
        }
        var reader = activeAdmin(capture.adminId);
        return reader == null ? null : {
            admin: reader,
            sessionKey: Sha256.encode('admin-preview:${value}').substr(0, 32)
        };
    }

    /**
        A pass a headless browser on this host sends to read one theme's
        preview pages and their assets, as the admin, for one minute: GET
        requests only, so an AI can look at the design it is editing.
    **/
    public static function captureTicket(adminId:Int, themeId:String):String {
        var ticket = SecureToken.generate(32);
        var now = Date.now().getTime();
        locked(() -> {
            for (key => pass in captures) {
                if (pass.expires <= now) {
                    captures.remove(key);
                }
            }
            captures.set(ticket, {
                adminId: adminId,
                themeId: themeId,
                expires: now + 60 * 1000,
                remaining: 400
            });
            return true;
        });
        return ticket;
    }

    static function capturable(path:String, themeId:String):Bool {
        if (path.indexOf("..") >= 0 || path.indexOf("//") >= 0) {
            return false;
        }
        var frame = '/admin/themes/${themeId}/preview/frame';
        return path == frame
            || StringTools.startsWith(path, '${frame}/')
            || StringTools.startsWith(path, '/admin/extension-assets/${themeId}/');
    }

    static function newToken():String {
        return 'hxa_${SecureToken.generate(32)}';
    }

    static function activeAdmin(id:Int):Null<Admin> {
        var admin = Admin.query.select(["id", "name", "role", "password"])
            .where("id", id)
            .where("active", 1)
            .limit(1)
            .first();
        return admin != null && Roles.exists(admin.role) ? admin : null;
    }

    static function belongsTo(link:AdminMcpLink, admin:Null<Admin>):Bool {
        return admin != null && link.admin_id == admin.id
            && link.auth_version == Sha256.encode(admin.password);
    }

    static function current(id:String):AdminMcpLink {
        var link = validId(id) ? AdminMcpLink.query.select(["admin_id", "token_hash", "auth_version", "expires_epoch"])
            .where("id", id)
            .limit(1)
            .first() : null;
        if (link == null) {
            throw invalidToken();
        }
        if (link.expires_epoch <= Date.now().getTime()) {
            throw new AdminMcpError("session_expired", "This MCP session has expired.");
        }
        return link;
    }

    static function invalidToken():AdminMcpError {
        return new AdminMcpError("invalid_token",
            "Supply the active bearer token for this MCP URL.");
    }

    /** Removes links an hour after they expire. **/
    public static function cleanup():Void {
        AdminMcpLink.query.where("expires_epoch", "<=", Date.now().getTime() - HISTORY).delete();
    }

    static function locked<T>(action:Void->T):T {
        mutex.acquire("admin-mcp");
        try {
            var result = action();
            mutex.release("admin-mcp");
            return result;
        } catch (error:Dynamic) {
            mutex.release("admin-mcp");
            throw error;
        }
    }
}
