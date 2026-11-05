package hx.press.media;

import hx.well.thread.MutexPool;

/** Use one lock order for dependency writes, content writes and library deletion. */
class MediaLocks {
    static final locks = new MutexPool();

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
