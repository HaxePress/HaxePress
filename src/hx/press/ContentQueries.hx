package hx.press;

import hx.press.Pagination.PageCursor;
import hx.press.data.ContentItemRecord;
import hx.press.data.ContentSummaryRecord;
import hx.press.data.QueryPage;
import hx.well.database.query.QueryBuilder;
import hx.press.model.ContentItem;
import hx.press.content.ContentTypes;
import hx.press.content.ContentFields;
import hx.press.content.ContentFields.ContentFieldFilter;

using StringTools;

class ContentQueries {
    public static inline var INDEX_SIZE = 12;

    static final summaryColumns = [
        "id",
        "content_type",
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
        "updated_at"
    ];

    static function summaryQuery(kind:String):QueryBuilder<ContentItem> {
        var columns = [for (column in summaryColumns) 'content_items.${column} AS ${column}'];
        var query = ContentItem.query.select(columns).where("content_items.content_type", kind);
        var type = ContentTypes.find(kind);
        if (type != null) {
            ContentFields.projectList(query, type, true);
        }
        return query;
    }

    public static function featured(kind:String):Null<ContentSummaryRecord> {
        return ContentCache.remember("items", "featured", [kind], () -> {
            var featured = summaryQuery(kind).where("status", "published")
                .where("featured", 1)
                .orderBy("content_items.published_at", "DESC")
                .orderBy("content_items.id", "DESC")
                .first();
            if (featured == null) {
                featured = summaryQuery(kind).where("status", "published")
                    .orderBy("content_items.published_at", "DESC")
                    .orderBy("content_items.id", "DESC")
                    .first();
            }
            return featured == null ? null : cast featured.toObject();
        });
    }

    public static function latest(excludeId:Int, kind:String,
            limit:Int = 6):Array<ContentSummaryRecord> {
        if (limit <= 0) {
            return [];
        }
        limit = Std.int(Math.min(24, limit));
        return ContentCache.remember("items", "home-latest", [kind, excludeId, limit], () -> {
            var query = summaryQuery(kind).where("status", "published");
            if (excludeId > 0)
                query.where("id", "!=", excludeId);
            query.orderBy("content_items.published_at", "DESC")
                .orderBy("content_items.id", "DESC")
                .limit(limit);
            return query.get().map(model -> cast model.toObject());
        });
    }

    public static function publishedCount(kind:String):Int {
        return ContentCache.remember("items", "published-count", [kind],
            () -> ContentItem.query.where("content_type", kind)
                .where("status", "published")
                .count());
    }

    public static function index(kind:String, query:String, category:String,
            cursor:Null<PageCursor>, tagId:Int = 0,
            filters:Array<ContentFieldFilter> = null):QueryPage<ContentSummaryRecord> {
        return ContentCache.remember("items", "index", [
            kind,
            query,
            category,
            Pagination.token(cursor),
            INDEX_SIZE,
            tagId,
            filters ?? []
        ], () -> {
            var items = filteredQuery(query, category, tagId, kind, filters ?? []);
            return fetchPage(items, "published_at", cursor, INDEX_SIZE);
        });
    }

    public static function indexCount(kind:String, query:String, category:String, tagId:Int = 0,
            filters:Array<ContentFieldFilter> = null):Int {
        return ContentCache.remember("items", "content-count",
            [kind, query, category, tagId, filters ?? []], () -> {
                var items = filteredQuery(query, category, tagId, kind, filters ?? []);
                return items.count();
            });
    }

    public static function designList(kind:String, limit:Int, category:String, search:String,
            tagId:Int, order:String, direction:String):Array<ContentSummaryRecord> {
        var size = Std.int(Math.max(1, Math.min(24, limit)));
        return ContentCache.remember("items", "theme-source",
            [kind, size, category, search, tagId, order, direction, ContentTypes.revision()],
            () -> {
                var query = filteredQuery(search, category, tagId, kind, []);
                query.orderBy('content_items.${order}', direction)
                    .orderBy("content_items.id", direction)
                    .limit(size);
                return query.get().map(model -> cast model.toObject());
            });
    }

    static function filteredQuery(search:String, category:String, tagId:Int, kind:String,
            filters:Array<ContentFieldFilter>):QueryBuilder<ContentItem> {
        var items = summaryQuery(kind);
        if (tagId > 0) {
            items.innerJoin("content_tags", "content_items.id", "=", "content_tags.content_id")
                .where("content_tags.tag_id", tagId);
        }
        items.where("content_items.status", "published");
        ContentFields.apply(items, filters);
        if (category != "") {
            items.where("content_items.category", category);
        }
        if (search != "") {
            var type = ContentTypes.find(kind);
            var pattern = '%${search.replace("!", "!!").replace("%", "!%").replace("_", "!_")}%';
            items.where(matches -> {
                matches.whereLike("content_items.title", pattern);
                if (ContentTypes.supports(type, "excerpt")) {
                    matches.orWhereLike("content_items.excerpt", pattern);
                }
                if (ContentTypes.supports(type, "body")) {
                    matches.orWhereLike("content_items.content", pattern);
                }
            });
        }
        return items;
    }

    static function fetchPage(query:QueryBuilder<ContentItem>, sortColumn:String,
            cursor:Null<PageCursor>, limit:Int):QueryPage<ContentSummaryRecord> {
        if (cursor != null) {
            addCursor(query, sortColumn, cursor);
        }
        var direction = cursor != null && cursor.before ? "ASC" : "DESC";
        query.orderBy('content_items.${sortColumn}', direction)
            .orderBy("content_items.id", direction)
            .limit(limit + 1);
        var rows:Array<ContentSummaryRecord> = query.get().map(model -> cast model.toObject());
        return Pagination.slice(rows, limit, cursor);
    }

    static function addCursor(query:QueryBuilder<ContentItem>, column:String,
            cursor:PageCursor):Void {
        if (cursor.value == null) {
            if (cursor.before) {
                query.where(matches -> {
                    matches.where(column, "IS NOT", null).orWhere(nullDates -> {
                        nullDates.where(column, "IS", null)
                            .where("content_items.id", ">", cursor.id);
                    });
                });
            } else {
                query.where(column, "IS", null).where("content_items.id", "<", cursor.id);
            }
        } else {
            var comparison = cursor.before ? ">" : "<";
            query.where(matches -> {
                matches.where(column, comparison, cursor.value).orWhere(sameDate -> {
                    sameDate.where(column, cursor.value)
                        .where("content_items.id", comparison, cursor.id);
                });
                if (!cursor.before) {
                    matches.orWhere(column, "IS", null);
                }
            });
        }
    }

    public static function publishedItem(slug:String, kind:String):Null<ContentItemRecord> {
        return ContentCache.remember("items", "published-by-slug", [kind, slug], () -> {
            var item = ContentItem.query.select(summaryColumns.concat(["content", "seo_title", "seo_description", "author_id"]))
                .where("slug", slug)
                .where("content_type", kind)
                .where("status", "published")
                .first();
            return item == null ? null : cast item.toObject();
        });
    }

    public static function publishedById(id:Int):Null<ContentItemRecord> {
        return ContentCache.remember("items", "published-home-id", [id, ContentTypes.revision()],
            () -> {
                var item = ContentItem.query.select(summaryColumns.concat(["content", "seo_title", "seo_description", "author_id"]))
                    .where("id", id)
                    .where("status", "published")
                    .whereInQuery("content_type", ContentTypes.publicKeys())
                    .first();
                return item == null ? null : cast item.toObject();
            });
    }

    public static function related(id:Int, kind:String):Array<ContentSummaryRecord> {
        return ContentCache.remember("items", "related", [kind, id, 3], () -> {
            var query = summaryQuery(kind).where("status", "published")
                .where("id", "!=", id)
                .orderBy("content_items.published_at", "DESC")
                .orderBy("content_items.id", "DESC")
                .limit(3);
            return query.get().map(model -> cast model.toObject());
        });
    }
}
