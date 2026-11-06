package hx.press.media;

import hx.well.thread.MutexPool;

/** Use one lock order for dependency writes, content writes and library deletion. */
class MediaLocks {
    static final locks = new MutexPool();

    /** Held for a plugin that declares the `media` lock while its routes and tasks run. **/
    public static function acquire():Void {
        locks.acquire("media");
    }

    public static function release():Void {
        locks.release("media");
    }

    public static function run<T>(action:Void->T):T {
        locks.acquire("media");
        try {
            var result = action();
            locks.release("media");
            return result;
        } catch (error:Dynamic) {
            locks.release("media");
            throw error;
        }
    }
}
