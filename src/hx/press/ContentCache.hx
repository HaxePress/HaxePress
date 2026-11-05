package hx.press;

import haxe.Json;
import haxe.crypto.Md5;
import hx.well.facades.Cache;
import hx.well.facades.Environment;
import hx.well.internal.SecureToken;
import hx.well.thread.MutexPool;
import haxe.io.Path;
import hx.well.facades.Storage;

class ContentCache {
    static final locks = new MutexPool();

    static function prefix(domain:String):String {
        var configured = Environment.env("DB_PATH", "storage/cms.sqlite");
        var parent = Path.directory(configured);
        var disk = Storage.build({
            driver: "local",
            root: parent == "" ? "." : parent,
            read_only: true
        });
        var database = disk.path(Path.withoutDirectory(configured));
        return "cms:content:v5:" + Md5.encode(database) + ":" + domain;
    }

    static function locked<T>(key:String, callback:Void->T):T {
        locks.acquire(key);
        try {
            var result = callback();
            locks.release(key);
            return result;
        } catch (error:Dynamic) {
            locks.release(key);
            throw error;
        }
    }

    public static function revision(domain:String):String {
        var key = prefix(domain) + ":revision";
        return locked(key,
            () -> Cache.store().rememberForever(key, () -> SecureToken.generate(16)));
    }

    public static function remember<T>(domain:String, operation:String, parameters:Array<Dynamic>,
            callback:Void->T):T {
        var generation = revision(domain);
        var parameterHash = Md5.encode(Json.stringify(parameters));
        var key = prefix(domain) + ":" + generation + ":" + operation + ":" + parameterHash;
        return locked(key,
            () -> Cache.store().remember(key, ServerSettings.contentCacheTtl, callback));
    }

    static function invalidate(domain:String):Void {
        var key = prefix(domain) + ":revision";
        locked(key, () -> {
            Cache.store().forever(key, SecureToken.generate(16));
            return true;
        });
    }

    public static function changed(domain:String):Void {
        invalidate(domain);
    }

    public static function contentChanged():Void {
        invalidate("items");
    }

    public static function categoriesChanged():Void {
        invalidate("categories");
    }

    public static function settingsChanged():Void {
        invalidate("settings");
    }
}
