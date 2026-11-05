package hx.press.themes;

import haxe.Json;
import hx.concurrent.collection.SynchronizedMap;
import hx.press.themes.ThemeAiAccess.ThemeAiActor;
import hx.well.websocket.AbstractWebSocketHandler;
import hx.well.websocket.WebSocketSession;
import hx.well.thread.MutexPool;

private typedef ThemePeer = {
    var themeId:String;
    var adminId:Int;
    var browser:Bool;
    var authorization:String;
    var session:WebSocketSession;
    var handler:AbstractWebSocketHandler;
}

/** Each theme has one shared channel for authenticated editors and external AI clients. */
class ThemeCollaboration {
    static final mutex = new MutexPool();
    static final themes:Map<String, SynchronizedMap<String, ThemePeer>> = [];

    static function peers(themeId:String):Array<ThemePeer> {
        mutex.acquire("themes");
        var group = themes.get(themeId);
        var result = group == null ? [] : [for (peer in group.copy()) peer];
        mutex.release("themes");
        return result;
    }

    public static function attach(themeId:String, browser:Bool, authorization:String,
            actor:ThemeAiActor, session:WebSocketSession, handler:AbstractWebSocketHandler):Void {
        var peer:ThemePeer = {
            themeId: themeId,
            adminId: actor.id,
            browser: browser,
            authorization: authorization,
            session: session,
            handler: handler
        };
        mutex.acquire("themes");
        var group = themes.get(themeId);
        if (group == null) {
            group = SynchronizedMap.newStringMap();
            themes.set(themeId, group);
        }
        group.set(session.id, peer);
        mutex.release("themes");
        if (browser) {
            notify(peer, "permissions", {themeId: themeId, permissions: actor.permissions});
        }
        presenceChanged(themeId);
    }

    public static function detach(themeId:String, sessionId:String):Void {
        if (themeId == null) {
            return;
        }
        mutex.acquire("themes");
        var group = themes.get(themeId);
        var peer = group == null ? null : group.get(sessionId);
        if (group != null) {
            group.remove(sessionId);
            if (!group.iterator().hasNext()) {
                themes.remove(themeId);
            }
        }
        mutex.release("themes");
        if (peer != null) {
            if (peer.browser) {
                ThemeAiAccess.forgetBrowserCredential(peer.authorization);
            }
            presenceChanged(themeId);
        }
    }

    static function live(peer:ThemePeer):Bool {
        return peer.handler.getSession(peer.session.id) != null;
    }

    static function notify(peer:ThemePeer, event:String, data:Dynamic):Void {
        if (live(peer)) {
            peer.session.send(Json.stringify({
                jsonrpc: "2.0",
                method: "notifications/haxepress/" + event,
                params: data
            }));
        }
    }

    public static function presence(themeId:String):{browsers:Int, llms:Int} {
        var result = {browsers: 0, llms: 0};
        for (peer in peers(themeId)) {
            if (live(peer)) {
                if (peer.browser) {
                    result.browsers++;
                } else {
                    result.llms++;
                }
            }
        }
        return result;
    }

    static function broadcast(themeId:String, event:String, data:Dynamic):Void {
        for (peer in peers(themeId)) {
            if (!peer.browser || !live(peer)) {
                continue;
            }
            try {
                var actor = ThemeAiAccess.authenticateToken(themeId, peer.authorization);
                if (actor == null) {
                    peer.session.close();
                } else {
                    notify(peer, event, data);
                }
            } catch (_:Dynamic) {
                peer.session.close();
            }
        }
    }

    static function presenceChanged(themeId:String):Void {
        broadcast(themeId, "presence", presence(themeId));
    }

    public static function designChanged(themeId:String, version:Int, publishedVersion:Int):Void {
        broadcast(themeId, "design_changed", {
            themeId: themeId,
            version: version,
            publishedVersion: publishedVersion
        });
    }

    public static function permissionsChanged(themeId:String, adminId:Int):Void {
        for (peer in peers(themeId)) {
            if (peer.browser && peer.adminId == adminId && live(peer)) {
                var actor = ThemeAiAccess.authenticateToken(themeId, peer.authorization);
                if (actor == null) {
                    peer.session.close();
                } else {
                    notify(peer, "permissions", {themeId: themeId, permissions: actor.permissions});
                }
            }
        }
    }

    public static function revokeLlm(themeId:String, adminId:Int):Void {
        for (peer in peers(themeId)) {
            if (!peer.browser && peer.adminId == adminId) {
                detach(themeId, peer.session.id);
                peer.session.close();
            }
        }
    }
}
