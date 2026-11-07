package hx.press;

import haxe.Json;
import haxe.Serializer;
import haxe.Unserializer;
import haxe.crypto.Md5;
import haxe.ds.IntMap;
import haxe.ds.StringMap;
import haxe.io.Path;
#if (target.threaded)
import sys.thread.Mutex;
#else
import hx.well.thread.FakeMutex as Mutex;
#end
import hx.well.cache.FileSystemCacheStore;
import hx.well.facades.Cache;
import sys.FileSystem;
import hx.press.config.DatabaseConfig;
import hx.well.facades.Storage;
import hx.well.http.RequestStatic;
import hx.well.internal.SecureToken;
import hx.well.thread.MutexPool;

typedef HotEntry = {
    var value:Dynamic;
    var expiresAt:Float;
    var weight:Int;
}

typedef PrefixState = {
    var configured:String;
    var base:String;
}

typedef RequestRevisions = {
    var base:String;
    var tokens:Map<String, String>;
}

class ContentCache {
    static inline var REQUEST_REVISIONS = "hx.press.cache.revisions";
    static inline var REQUEST_UNCACHED = "hx.press.cache.uncached";
    static inline var HOT_BUDGET_BYTES = 4194304;
    static inline var HOT_ENTRY_LIMIT_BYTES = 262144;
    static inline var HOT_REFRESH_SECONDS = 60;

    static final locks = new MutexPool();
    static final hotLock = new Mutex();
    static final hotEntries:Map<String, HotEntry> = [];
    static var hotWeight = 0;
    static var prefixState:Null<PrefixState> = null;

    /**
        Revision tokens known to this process, by key, re-read from the cache
        at most once per `REVISION_SECONDS` and only while their file exists:
        deleting the cache files starts new revisions at once. This process
        changes them through `invalidate`, which updates them at once.
    **/
    static inline var REVISION_SECONDS = 1.0;

    static final knownRevisions:Map<String, {token:String, checkedAt:Float, file:String}> = [];
    static final revisionLock = new Mutex();
    static var revisionFiles:Null<FileSystemCacheStore> = null;

    /**
        Small records that most requests read. Search, list and editor results
        stay in the file cache only.
    **/
    static final hotOperations:Map<String, Map<String, Bool>> = [
        "settings" => ["public" => true],
        "extensions" => [
            "active-theme" => true,
            "active-directory" => true,
            "package" => true,
            "event" => true,
            "theme-design" => true,
            "translations" => true,
            "translation-package" => true,
            "active-translation-packages" => true
        ],
        "navigation" => ["location" => true, "region" => true],
        "categories" => ["navigation" => true],
        "structure" => ["type" => true, "public-base" => true]
    ];

    static function isHot(domain:String, operation:String):Bool {
        var operations = hotOperations.get(domain);
        return operations != null && operations.exists(operation);
    }

    static function currentPrefix():String {
        return databasePrefix(DatabaseConfig.sqlitePath());
    }

    static function prefix(domain:String):String {
        return '${currentPrefix()}:${domain}';
    }

    /** The database part of every key, recomputed only when DB_PATH changes. */
    static function databasePrefix(configured:String):String {
        var state = prefixState;
        if (state != null && state.configured == configured) {
            return state.base;
        }
        var parent = Path.directory(configured);
        var disk = Storage.build({
            driver: "local",
            root: parent == "" ? "." : parent,
            read_only: true
        });
        var database = disk.path(Path.withoutDirectory(configured));
        var base = 'cms:content:v5:${Md5.encode(database)}';
        prefixState = {configured: configured, base: base};
        return base;
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

    /**
        Revisions read during the current HTTP request, for the database the request
        uses. A WebSocket session keeps its upgrade request for every message, so it
        always reads the stored value. The upgrade check runs once per request.
    **/
    static function requestRevisions(base:String):Null<RequestRevisions> {
        var request = RequestStatic.request();
        if (request == null) {
            return null;
        }
        var revisions:Null<RequestRevisions> = request.getAttribute(REQUEST_REVISIONS);
        if (revisions != null) {
            if (revisions.base != base) {
                revisions.base = base;
                revisions.tokens = new Map<String, String>();
            }
            return revisions;
        }
        if (request.getAttribute(REQUEST_UNCACHED, false)) {
            return null;
        }
        var upgrade = request.header("Upgrade");
        if (upgrade != null && upgrade.toLowerCase() == "websocket") {
            request.setAttribute(REQUEST_UNCACHED, true);
            return null;
        }
        revisions = {base: base, tokens: new Map<String, String>()};
        request.setAttribute(REQUEST_REVISIONS, revisions);
        return revisions;
    }

    public static function revision(domain:String):String {
        var base = currentPrefix();
        var revisions = requestRevisions(base);
        if (revisions != null) {
            var known = revisions.tokens.get(domain);
            if (known != null) {
                return known;
            }
        }
        var key = '${base}:${domain}:revision';
        var now = Sys.time();
        revisionLock.acquire();
        var known = knownRevisions.get(key);
        revisionLock.release();
        var token:String;
        if (known != null && now - known.checkedAt < REVISION_SECONDS
            && FileSystem.exists(known.file)) {
            token = known.token;
        } else {
            token = locked(key,
                () -> Cache.store().rememberForever(key, () -> SecureToken.generate(16)));
            knowRevision(key, token, now);
        }
        if (revisions != null) {
            revisions.tokens.set(domain, token);
        }
        return token;
    }

    public static function remember<T>(domain:String, operation:String, parameters:Array<Dynamic>,
            callback:Void->T):T {
        var generation = revision(domain);
        var parameterHash = Md5.encode(Json.stringify(parameters));
        var key = '${prefix(domain)}:${generation}:${operation}:${parameterHash}';
        var hot = isHot(domain, operation);
        if (hot) {
            var cached:Null<T> = hotValue(key);
            if (cached != null) {
                return cached;
            }
        }
        var computed = false;
        var value:T = locked(key,
            () -> Cache.store().remember(key, ServerSettings.contentCacheTtl, () -> {
                computed = true;
                return callback();
            }));
        if (hot && value != null) {
            // A record read from a file keeps its unknown remaining lifetime, so it is refreshed sooner.
            var lifetime = computed ? ServerSettings.contentCacheTtl : Std.int(Math.min(ServerSettings.contentCacheTtl,
                HOT_REFRESH_SECONDS));
            storeHot(key, value, lifetime);
        }
        return value;
    }

    static function hotValue(key:String):Dynamic {
        hotLock.acquire();
        var entry = hotEntries.get(key);
        hotLock.release();
        if (entry == null || entry.expiresAt < Sys.time()) {
            return null;
        }
        return copyValue(entry.value);
    }

    static function storeHot(key:String, value:Dynamic, lifetime:Int):Void {
        var weight = Serializer.run(value).length;
        if (weight > HOT_ENTRY_LIMIT_BYTES) {
            return;
        }
        var entry:HotEntry = {
            value: copyValue(value),
            expiresAt: Sys.time() + lifetime,
            weight: weight
        };
        hotLock.acquire();
        var previous = hotEntries.get(key);
        if (previous != null) {
            hotWeight -= previous.weight;
        }
        if (hotWeight + weight > HOT_BUDGET_BYTES) {
            hotEntries.clear();
            hotWeight = 0;
        }
        hotEntries.set(key, entry);
        hotWeight += weight;
        hotLock.release();
    }

    /** Callers receive private objects, as they do from the file cache. */
    static function copyValue(value:Dynamic):Dynamic {
        switch Type.typeof(value) {
            case TNull | TInt | TFloat | TBool | TFunction:
                return value;
            case TObject:
                var copy:Dynamic = {};
                for (field in Reflect.fields(value)) {
                    Reflect.setField(copy, field, copyValue(Reflect.field(value, field)));
                }
                return copy;
            case TClass(type) if (type == String || type == Date):
                return value;
            case TClass(type) if (type == Array):
                var source:Array<Dynamic> = value;
                return [for (entry in source) copyValue(entry)];
            case TClass(type) if (type == StringMap):
                var source:StringMap<Dynamic> = value;
                var copy = new StringMap<Dynamic>();
                for (key => entry in source) {
                    copy.set(key, copyValue(entry));
                }
                return copy;
            case TClass(type) if (type == IntMap):
                var source:IntMap<Dynamic> = value;
                var copy = new IntMap<Dynamic>();
                for (key => entry in source) {
                    copy.set(key, copyValue(entry));
                }
                return copy;
            default:
                return Unserializer.run(Serializer.run(value));
        }
    }

    static function invalidate(domain:String):Void {
        var base = currentPrefix();
        var key = '${base}:${domain}:revision';
        var token = SecureToken.generate(16);
        locked(key, () -> {
            Cache.store().forever(key, token);
            return true;
        });
        knowRevision(key, token, Sys.time());
        var revisions = requestRevisions(base);
        if (revisions != null) {
            revisions.tokens.set(domain, token);
        }
    }

    static function knowRevision(key:String, token:String, checkedAt:Float):Void {
        revisionLock.acquire();
        var known = knownRevisions.get(key);
        var file = known != null ? known.file : revisionFile(key);
        knownRevisions.set(key, {token: token, checkedAt: checkedAt, file: file});
        revisionLock.release();
    }

    /** Where the default file cache keeps an entry. */
    static function revisionFile(key:String):String {
        if (revisionFiles == null) {
            revisionFiles = new FileSystemCacheStore();
        }
        return '${revisionFiles.path}/${revisionFiles.cacheKey(key)}';
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
