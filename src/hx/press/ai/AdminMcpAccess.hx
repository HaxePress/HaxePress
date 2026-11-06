package hx.press.ai;

import haxe.Exception;
import haxe.crypto.Sha256;
import hx.press.access.Roles;
import hx.press.model.Admin;
import hx.press.themes.ThemeMcpHost;
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

private typedef AdminMcpTicket = {
    var authorization:String;
    var sessionId:String;
    var browserSession:Null<String>;
    var expires:Float;
    var remaining:Int;
}

private typedef RemoteSession = {
    var id:String;
    var adminId:Int;
    var authVersion:String;
    var profile:String;
    var origin:String;
    var expires:Float;
    var tokenHash:String;
    var firstSeenAt:Null<Float>;
    var lastSeenAt:Null<Float>;
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
    public static inline var BROWSER_HEADER = "X-HaxePress-Browser-Session";
    public static inline var TICKET_HEADER = "X-HaxePress-Admin-Request";
    public static inline var INTERNAL = "hx.press.admin-mcp.internal";
    static inline var LIFETIME = 24 * 60 * 60 * 1000;
    static inline var HISTORY = 60 * 60 * 1000;
    static final sessions:Map<String, RemoteSession> = [];
    static final owners:Map<Int, Array<String>> = [];
    static final tickets:Map<String, AdminMcpTicket> = [];
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

    public static function issue(admin:Admin, profile:String):Dynamic {
        var id = SecureToken.generate(32);
        var address = origin();
        var token = newToken();
        var session:RemoteSession = {
            id: id,
            adminId: admin.id,
            authVersion: Sha256.encode(admin.password),
            profile: profile,
            origin: address,
            expires: Date.now().getTime() + LIFETIME,
            tokenHash: Sha256.encode(token),
            firstSeenAt: null,
            lastSeenAt: null
        };
        locked(() -> {
            var ids = activeIds(admin);
            if (ids.length >= 8) {
                throw new AdminMcpError("connection_limit",
                    "End an MCP session before creating another.", 429);
            }
            ids.push(id);
            owners.set(admin.id, ids);
            sessions.set(id, session);
            return true;
        });
        AdminMcpSockets.changed(admin.id);
        return {
            id: id,
            profile: profile,
            url: '${address}${path(id)}',
            token: token,
            expires: session.expires
        };
    }

    public static function state(admin:Admin):Dynamic {
        return locked(() -> {
            var connections = activeIds(admin).map(id -> {
                var session = sessions.get(id);
                return {
                    id: id,
                    profile: session.profile,
                    url: '${session.origin}${path(id)}',
                    expires: session.expires,
                    firstSeenAt: session.firstSeenAt,
                    lastSeenAt: session.lastSeenAt
                };
            });
            return {sessions: connections, hosted: ThemeMcpHost.available()};
        });
    }

    public static function recordSeen(id:String):Void {
        locked(() -> {
            var session = sessions.get(id);
            var now = Date.now().getTime();
            if (session != null && now < session.expires) {
                session.firstSeenAt = session.firstSeenAt ?? now;
                session.lastSeenAt = Math.max(session.lastSeenAt ?? now, now);
            }
            return true;
        });
    }

    public static function end(adminId:Int, id:String):Void {
        locked(() -> {
            var session = validId(id) ? sessions.get(id) : null;
            if (session == null || session.adminId != adminId) {
                throw new AdminMcpError("session_inactive", "This MCP session is inactive.", 404);
            }
            sessions.remove(id);
            var ids = owners.get(adminId);
            if (ids != null) {
                ids.remove(id);
            }
            return true;
        });
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
        var hash = Sha256.encode(authorization.substr(7));
        var session = locked(() -> {
            var candidate = current(id);
            if (candidate.tokenHash != hash) {
                throw invalidToken();
            }
            return candidate;
        });
        var admin = activeAdmin(session.adminId);
        if (!belongsTo(session, admin)) {
            throw invalidToken();
        }
        return {admin: admin, sessionId: id, expires: session.expires};
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

    public static function delegate(authorization:String, sessionId:String,
            browserSession:Null<String>):String {
        var ticket = SecureToken.generate(32);
        locked(() -> {
            tickets.set(ticket, {
                authorization: authorization,
                sessionId: sessionId,
                browserSession: browserSession,
                expires: Date.now().getTime() + 30 * 1000,
                remaining: 6
            });
            return true;
        });
        return ticket;
    }

    public static function delegated(request:Request):Null<{admin:Admin, sessionKey:String}> {
        var value = request.header(TICKET_HEADER, "");
        if (!validId(value)
            || (request.ip != "127.0.0.1" && request.ip != "::ffff:127.0.0.1")
            || request.header("Forwarded") != null
            || request.header("X-Forwarded-For") != null
            || request.header("X-Real-IP") != null) {
            return null;
        }
        var ticket = locked(() -> {
            var grant = tickets.get(value);
            if (grant == null || grant.remaining <= 0 || grant.expires <= Date.now().getTime()) {
                return null;
            }
            grant.remaining--;
            return grant;
        });
        if (ticket == null) {
            return null;
        }
        if (ticket.browserSession != null) {
            var admin = browser(ticket.browserSession);
            return admin == null ? null : {admin: admin, sessionKey: ticket.browserSession};
        }
        var actor = authenticate(ticket.sessionId, ticket.authorization);
        return {
            admin: actor.admin,
            sessionKey: Sha256.encode('admin-mcp:${actor.sessionId}').substr(0, 32)
        };
    }

    public static function discardTicket(ticket:String):Void {
        locked(() -> tickets.remove(ticket));
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

    static function belongsTo(session:RemoteSession, admin:Null<Admin>):Bool {
        return admin != null && session.adminId == admin.id
            && session.authVersion == Sha256.encode(admin.password);
    }

    static function activeIds(admin:Admin):Array<String> {
        var now = Date.now().getTime();
        var version = Sha256.encode(admin.password);
        var ids = owners.get(admin.id) ?? [];
        return ids.filter(id -> {
            var session = sessions.get(id);
            return session != null && session.expires > now && session.authVersion == version;
        });
    }

    static function current(id:String):RemoteSession {
        var session = validId(id) ? sessions.get(id) : null;
        if (session == null) {
            throw invalidToken();
        }
        if (session.expires <= Date.now().getTime()) {
            throw new AdminMcpError("session_expired", "This MCP session has expired.");
        }
        return session;
    }

    static function invalidToken():AdminMcpError {
        return new AdminMcpError("invalid_token",
            "Supply the active bearer token for this MCP URL.");
    }

    public static function cleanup():Void {
        var now = Date.now().getTime();
        locked(() -> {
            for (id in [for (id in sessions.keys()) id]) {
                var session = sessions.get(id);
                if (session.expires + HISTORY <= now) {
                    sessions.remove(id);
                    var ids = owners.get(session.adminId);
                    if (ids != null) {
                        ids.remove(id);
                        if (ids.length == 0) {
                            owners.remove(session.adminId);
                        }
                    }
                }
            }
            return true;
        });
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
