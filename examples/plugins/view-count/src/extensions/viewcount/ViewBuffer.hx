package extensions.viewcount;

import hx.well.facades.DBStatic;
import hx.well.facades.Storage;
import hx.well.internal.SecureToken;
#if target.threaded
import sys.thread.Mutex;
#end

/**
    Collects counted views and writes them to the database once a minute,
    so a page view writes nothing to the database. Each view adds one to
    the count of its content item and country.

    The JVM keeps the counts in memory and writes them when the plugin
    stops too. PHP serves each request in a new process, so a view appends
    one line to the file of its minute on the local disk; a minute is
    written once it has ended and its last writers are done.
**/
class ViewBuffer {
    /** The plugin's job that writes the counts. **/
    public static inline var JOB = "flush";

    public static inline var INTERVAL_SECONDS = 60;

    /** How many counts one transaction writes at most. **/
    static inline var BATCH = 500;

    #if target.threaded
    static final lock = new Mutex();
    static var pending:Map<String, Int> = [];
    #else
    static inline var FOLDER = "view-count/pending";
    static inline var MINUTE_MS = 60000;

    /** Time for the writers of a minute that has ended to finish their line. **/
    static inline var SETTLE_MS = 5000;

    /** A file a flush claimed but did not finish is taken again after this many minutes. **/
    static inline var RECLAIM_MINUTES = 10;
    #end

    /** Counts one view of the content item `id` from `country`. **/
    public static function add(id:Int, type:String, country:String):Void {
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

    /**
        Writes the counts collected so far: totals per content item, and per
        country as well when `countries` is set.
    **/
    public static function flush(countries:Bool):Void {
        var views = take();
        var start = 0;
        while (start < views.length) {
            var batch = views.slice(start, start + BATCH);
            DBStatic.transaction(() -> {
                ViewCounts.add(batch);
                if (countries) {
                    CountryViewData.add(batch);
                }
            });
            start += BATCH;
        }
    }

    /** The counts collected so far, as `{content: {id, type}, country, count}`, removed from the buffer. **/
    static function take():Array<Dynamic> {
        #if target.threaded
        lock.acquire();
        var counts = pending;
        pending = [];
        lock.release();
        return views(counts);
        #else
        var disk = Storage.disk("local");
        if (!disk.directoryExists(FOLDER)) {
            return [];
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
        return views(counts);
        #end
    }

    static function views(counts:Map<String, Int>):Array<Dynamic> {
        var result:Array<Dynamic> = [];
        for (key => count in counts) {
            var parts = key.split("\t");
            var id = parts.length == 3 ? Std.parseInt(parts[0]) : null;
            if (id == null || id <= 0) {
                continue;
            }
            result.push({
                content: {id: id, type: parts[1]},
                country: parts[2],
                count: count
            });
        }
        return result;
    }
}
