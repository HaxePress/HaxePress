package hx.press.plugins;

import haxe.Exception;
import haxe.ThreadLocal;
import hx.well.HxWell;
import hx.well.middleware.AbstractMiddleware;
#if target.threaded
import sys.thread.Mutex;
#else
import hx.well.thread.FakeMutex as Mutex;
#end

/**
    Middleware a plugin runs on every request. A plugin adds it in
    `onCreate` and removes it in `onDestroy`, like its routes; when the
    plugin stops, the runtime also removes any it left. Plugin middleware
    runs after the application's global middleware and before route
    middleware, in the order it was added, and HxWell creates and disposes
    an instance per request. A request keeps the list it started with, so a
    removal applies to the requests that start after it.
**/
class PluginMiddleware {
    static final writes = new Mutex();
    static final collecting = new ThreadLocal<Array<PluginMiddleware>>();

    /** The global middleware of the application, before any plugin added its own. **/
    static var application:Null<Array<Class<AbstractMiddleware>>> = null;

    static var added:Array<PluginMiddleware> = [];

    public final type:Class<AbstractMiddleware>;

    function new(type:Class<AbstractMiddleware>) {
        this.type = type;
    }

    /** Runs `type` on every request and returns the handle that removes it. **/
    public static function add(type:Class<AbstractMiddleware>):PluginMiddleware {
        if (type == null) {
            throw new Exception("Choose the middleware class to add.");
        }
        var middleware = new PluginMiddleware(type);
        writes.acquire();
        var next = added.copy();
        next.push(middleware);
        publish(next);
        writes.release();
        var collected = collecting.get();
        if (collected != null) {
            collected.push(middleware);
        }
        return middleware;
    }

    /** Stops running middleware added with `add`. Removing it again does nothing. **/
    public static function remove(middleware:PluginMiddleware):Void {
        if (middleware == null) {
            return;
        }
        writes.acquire();
        if (added.contains(middleware)) {
            publish(added.filter(item -> item != middleware));
        }
        writes.release();
    }

    /**
        Runs a plugin's creation and returns the middleware it added, so the
        runtime can remove what the plugin leaves when it stops. A failed
        creation removes its middleware before the error is rethrown.
    **/
    public static function collect(callback:Void->Void):Array<PluginMiddleware> {
        var previous = collecting.get();
        var collected:Array<PluginMiddleware> = [];
        collecting.set(collected);
        try {
            callback();
        } catch (error:Dynamic) {
            collecting.set(previous);
            for (middleware in collected) {
                remove(middleware);
            }
            throw error;
        }
        collecting.set(previous);
        if (previous != null) {
            for (middleware in collected) {
                previous.push(middleware);
            }
        }
        return collected;
    }

    /** Publishes a new list; requests read `HxWell.middlewares` once when they start. **/
    static function publish(next:Array<PluginMiddleware>):Void {
        if (application == null) {
            application = HxWell.middlewares;
        }
        var core:Array<Class<AbstractMiddleware>> = application;
        var types = [for (middleware in next) middleware.type];
        added = next;
        HxWell.middlewares = types.length == 0 ? core : core.concat(types);
    }
}
