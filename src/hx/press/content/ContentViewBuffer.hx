package hx.press.content;

import hx.press.packages.PackageData;
import hx.press.plugins.PluginRuntime;
import hx.well.facades.Storage;
import hx.well.internal.SecureToken;
#if target.threaded
import sys.thread.Mutex;
#end

/**
    Collects the views `ContentViews.counted` accepts and gives them to
    plugins once a minute with the `content.viewed` hook, so a page view
    writes nothing to the database. Each view adds one to the count of its
    content item and country.

    The JVM keeps the counts in memory and hands them over at shutdown too.
    PHP serves each request in a new process, so a view appends one line to
    the file of its minute in `storage/content-views`; a minute is handed
    over once it has ended and its last writers are done.
**/
class ContentViewBuffer {
    /** How many counts one `content.viewed` hook receives at most. **/
    public static inline var BATCH = 500;

    /** The core job that hands the counts to plugins. **/
    public static inline var JOB = "content-views";

    public static inline var INTERVAL_SECONDS = 60;

    #if target.threaded
    static final lock = new Mutex();
    static var pending:Map<String, Int> = [];
    #else
    static inline var FOLDER = "content-views";
    static inline var MINUTE_MS = 60000;

    /** Time for the writers of a minute that has ended to finish their line. **/
    static inline var SETTLE_MS = 5000;

    /** A file a flush claimed but did not finish is taken again after this many minutes. **/
    static inline var RECLAIM_MINUTES = 10;
    #end

    /** Whether an active plugin receives `content.viewed`. **/
    public static function wanted():Bool {
        return PackageData.forEvent("content.viewed", "plugin").length > 0;
    }

    /** Counts one view of the content item `id` from `country`. **/
    public static function add(id:Int, type:String, country:String):Void {
        if (!wanted()) {
            return;
        }
        var key = '${id}\t${type}\t${country}';
        #if target.threaded
        lock.acquire();
        var count = pending.get(key) ?? 0;
        pending.set(key, count + 1);
        lock.release();
        #else
        var minute = Math.floor(Date.now().getTime() / MINUTE_MS);
        Storage.disk("local").append('${FOLDER}/${minute}.log', '${key}\n', "");
        #end
    }

    /** Hands the counts collected so far to the plugins. **/
    public static function flush():Void {
        #if target.threaded
        lock.acquire();
        var taken = pending;
        pending = [];
        lock.release();
        send(taken);
        #else
        var disk = Storage.disk("local");
        if (!disk.directoryExists(FOLDER)) {
            return;
        }
        var now = Date.now().getTime();
        var currentMinute = Math.floor(now / MINUTE_MS);
        var counts:Map<String, Int> = [];
        for (file in disk.files(FOLDER)) {
            var parts = file.substr(FOLDER.length + 1).split(".");
            var minute = Std.parseInt(parts[0]);
            if (minute == null) {
                continue;
            }
            var ready = parts.length == 2 && parts[1] == "log"
                && (minute + 1) * 1.0 * MINUTE_MS + SETTLE_MS <= now;
            var claimedAt = parts.length == 4
                && parts[3] == "claimed" ? Std.parseInt(parts[1]) : null;
            var abandoned = claimedAt != null && claimedAt + RECLAIM_MINUTES <= currentMinute;
            if (!ready && !abandoned) {
                continue;
            }
            // Renaming claims the file: a flush in another process cannot take it too.
            var token = SecureToken.generate(16);
            var claimed = '${FOLDER}/${minute}.${currentMinute}.${token}.claimed';
            var moved = false;
            try {
                moved = disk.move(file, claimed);
            } catch (error:Dynamic) {
                moved = false;
            }
            if (!moved) {
                continue;
            }
            var text = disk.get(claimed) ?? "";
            disk.delete(claimed);
            for (line in text.split("\n")) {
                if (line != "") {
                    var count = counts.get(line) ?? 0;
                    counts.set(line, count + 1);
                }
            }
        }
        send(counts);
        #end
    }

    static function send(counts:Map<String, Int>):Void {
        var batch:Array<Dynamic> = [];
        for (key => count in counts) {
            var parts = key.split("\t");
            var id = parts.length == 3 ? Std.parseInt(parts[0]) : null;
            if (id == null || id <= 0) {
                continue;
            }
            batch.push({
                content: {id: id, type: parts[1]},
                country: parts[2],
                count: count
            });
            if (batch.length == BATCH) {
                PluginRuntime.viewed(batch);
                batch = [];
            }
        }
        if (batch.length > 0) {
            PluginRuntime.viewed(batch);
        }
    }
}
