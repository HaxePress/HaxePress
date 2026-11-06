package hx.press;

import hx.press.ContentCache;
import hx.press.Pagination;
import hx.press.Pagination.PageCursor;
import hx.press.data.ContentItemRecord;
import hx.press.data.ContentSummaryRecord;
import hx.press.data.QueryPage;
import hx.well.database.query.QueryBuilder;
import hx.press.model.ContentItem;
import hx.press.content.ContentTypes;
import hx.press.model.ContentType;
import hx.press.content.ContentFields;

typedef ContentSummary = {
    > ContentSummaryRecord,
    var version:Int;
    var author_id:Int;
    var scheduled_epoch:Float;
}

class ContentData {
    public static inline var PAGE_SIZE = 20;
    public static final summaryColumns = [
        "id",
        "title",
        "slug",
        "excerpt",
        "category",
        "image",
        "image_alt",
        "status",
        "featured",
        "reading_minutes",
        "published_at",
        "updated_at",
        "content_type",
        "version",
        "author_id",
        "scheduled_epoch"
    ];
    public static final editorColumns = summaryColumns.concat(["content", "seo_title", "seo_description", "previous_status", "created_at"]);

    static function filtered(kind:String, search:String, status:String, author:Int,
            capabilities:Array<String> = null):QueryBuilder<ContentItem> {
        var query = ContentItem.query.select(summaryColumns);
        if (kind != "") {
            query.where("content_type", kind);
            var type = ContentTypes.find(kind);
            if (type != null) {
                ContentFields.projectList(query, type, false);
            }
        } else {
            var types = ContentType.query.select(["key"]);
            if (capabilities == null) {
                ContentTypes.available(types);
            } else {
                ContentTypes.accessible(types, capabilities);
            }
            query.whereInQuery("content_type", types);
        }
        if (author > 0) {
            query.where("author_id", author);
        }
        if (status != "") {
            query.where("status", status);
        } else {
            query.where("status", "!=", "trash");
        }
        if (search != "") {
            var escaped = StringTools.replace(StringTools.replace(StringTools.replace(search, "!",
                "!!"), "%", "!%"), "_", "!_");
            var pattern = '%${escaped}%';
            query.where(matches -> {
                matches.whereLike("title", pattern).orWhereLike("slug", pattern);
            });
        }
        return query;
    }

    public static function page(kind:String, search:String, status:String, author:Int,
            cursor:Null<PageCursor>):QueryPage<ContentSummary> {
        return ContentCache.remember("items", "cms-list",
            [kind, search, status, author, Pagination.token(cursor), PAGE_SIZE], () -> {
                var query = filtered(kind, search, status, author);
                if (cursor != null && cursor.value != null) {
                    var comparison = cursor.before ? ">" : "<";
                    query.where(matches -> {
                        matches.where("updated_at", comparison, cursor.value).orWhere(sameTime -> {
                            sameTime.where("updated_at", cursor.value)
                                .where("id", comparison, cursor.id);
                        });
                    });
                }
                var direction = cursor != null && cursor.before ? "ASC" : "DESC";
                var rows:Array<ContentSummary> = query.orderBy("updated_at", direction)
                    .orderBy("id", direction)
                    .limit(PAGE_SIZE + 1)
                    .get()
                    .map(model -> cast model.toObject());
                return Pagination.slice(rows, PAGE_SIZE, cursor);
            });
    }

    public static function count(kind:String, search:String = "", status:String = "",
            author:Int = 0, capabilities:Array<String> = null):Int {
        return ContentCache.remember("items", "cms-count",
            [kind, search, status, author, capabilities, ContentTypes.revision()],
            () -> filtered(kind, search, status, author, capabilities).count());
    }

    public static function recent(author:Int,
            capabilities:Array<String> = null):Array<ContentSummary> {
        return ContentCache.remember("items", "cms-recent",
            [author, capabilities, 5, ContentTypes.revision()], () -> {
                return filtered("", "", "", author,
                    capabilities).orderBy("updated_at", "DESC")
                    .orderBy("id", "DESC")
                    .limit(5)
                    .get()
                    .map(model -> cast model.toObject());
            });
    }

    public static function detail(id:Int, kind:String):Null<ContentItemRecord> {
        return ContentCache.remember("items", "cms-editor", [kind, id], () -> {
            var row = ContentItem.query.select(editorColumns)
                .where("id", id)
                .where("content_type", kind)
                .first();
            return row == null ? null : cast row.toObject();
        });
    }
}
