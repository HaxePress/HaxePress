package extensions.newsletter;

import hx.press.ContentCache;
import hx.press.Pagination;
import hx.press.Pagination.PageCursor;
import hx.press.data.QueryPage;
import hx.press.database.DatabaseDate;

typedef SubscriberRecord = {
    var id:Int;
    var email:String;
    var created_at:DatabaseDate;
}

class SubscriberData {
    public static inline var PAGE_SIZE = 30;
    public static inline var EXPORT_BATCH_SIZE = 100;

    public static function count():Int {
        return ContentCache.remember("subscribers", "count", [], () -> Subscriber.query.count());
    }

    public static function page(cursor:Null<PageCursor>):QueryPage<SubscriberRecord> {
        return ContentCache.remember("subscribers", "page", [Pagination.token(cursor), PAGE_SIZE],
            () -> {
                var query = Subscriber.query.select(["id", "email", "created_at"]);
                if (cursor != null)
                    query.where("id", cursor.before ? ">" : "<", cursor.id);
                var direction = cursor != null && cursor.before ? "ASC" : "DESC";
                var rows:Array<SubscriberRecord> = [
                    for (row in query.orderBy("id", direction).limit(PAGE_SIZE + 1).get())
                        (cast row.toObject() : SubscriberRecord)
                ];
                return Pagination.slice(rows, PAGE_SIZE, cursor);
            });
    }

    public static function exportLimit():Int {
        var row = Subscriber.query.select(["id"]).orderBy("id", "DESC").limit(1).first();
        return row == null ? 0 : row.id;
    }

    public static function exportBatch(after:Int, lastId:Int):Array<SubscriberRecord> {
        var rows = Subscriber.query.select(["id", "email", "created_at"])
            .where("id", ">", after)
            .where("id", "<=", lastId)
            .orderBy("id")
            .limit(EXPORT_BATCH_SIZE)
            .get();
        return [for (row in rows) (cast row.toObject() : SubscriberRecord)];
    }
}
