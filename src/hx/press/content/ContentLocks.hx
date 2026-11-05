package hx.press.content;

import hx.well.thread.MutexPool;

/** A shared lock order keeps definition edits and document writes consistent. */
class ContentLocks {
    static final locks = new MutexPool();

    public static function run<T>(key:String, action:Void->T):T {
        locks.acquire(key);
        try {
            var result = action();
            locks.release(key);
            return result;
        } catch (error:Dynamic) {
            locks.release(key);
            throw error;
        }
    }
}
