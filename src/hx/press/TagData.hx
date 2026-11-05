package hx.press;

import hx.press.CategoryData;
import hx.press.ContentCache;
import hx.press.Pagination;
import hx.press.Pagination.PageCursor;
import hx.press.data.QueryPage;
import hx.well.database.query.QueryBuilder;
import hx.press.model.ContentTag;
import hx.press.model.Tag;

typedef TagRecord = {
    var id:Int;
    var name:String;
    var slug:String;
    var description:String;
}

typedef TagSummary = {
    > TagRecord,
    var items:Int;
}

class TagData {
    public static inline var PAGE_SIZE = 20;
    public static inline var MAX_TAGS = 10;

    static function filter(query:QueryBuilder<Tag>, search:String):Void {
        var prefix = CategoryData.key(CategoryData.normalize(search)).substr(0, 80);
        if (prefix != "") {
            query.where("name_key", ">=", prefix)
                .where("name_key", "<", prefix + String.fromCharCode(0x10FFFF));
        }
    }

    public static function page(search:String, cursor:Null<PageCursor>):QueryPage<TagSummary> {
        var prefix = CategoryData.key(CategoryData.normalize(search)).substr(0, 80);
        var contentRevision = ContentCache.revision("items");
        return ContentCache.remember("tags", "manage",
            [prefix, Pagination.token(cursor), PAGE_SIZE, contentRevision], () -> {
                var usageCount = ContentTag.query.selectCount()
                    .whereColumn("content_tags.tag_id", "tags.id");
                var query = Tag.query.select(["id", "name", "slug", "description"])
                    .selectSub(usageCount, "items");
                filter(query, prefix);
                if (cursor != null) {
                    query.where("id", cursor.before ? "<" : ">", cursor.id);
                }
                var direction = cursor != null && cursor.before ? "DESC" : "ASC";
                var rows:Array<TagSummary> = [
                    for (row in query.orderBy("id", direction).limit(PAGE_SIZE + 1).get())
                        (cast row.toObject() : TagSummary)
                ];
                return Pagination.slice(rows, PAGE_SIZE, cursor);
            });
    }

    public static function count(search:String):Int {
        var prefix = CategoryData.key(CategoryData.normalize(search)).substr(0, 80);
        return ContentCache.remember("tags", "count", [prefix], () -> {
            var query = Tag.query.select(["id"]);
            filter(query, prefix);
            return query.count();
        });
    }

    public static function options(search:String):Array<TagRecord> {
        var prefix = CategoryData.key(CategoryData.normalize(search)).substr(0, 80);
        return ContentCache.remember("tags", "options", [prefix, 20], () -> {
            var query = Tag.query.select(["id", "name", "slug", "description"]);
            filter(query, prefix);
            return [
                for (row in query.orderBy("name_key").limit(20).get())
                    (cast row.toObject() : TagRecord)
            ];
        });
    }

    public static function named(slug:String):Null<TagRecord> {
        return ContentCache.remember("tags", "slug", [slug], () -> {
            var row = Tag.query.select(["id", "name", "slug", "description"])
                .where("slug", slug)
                .limit(1)
                .first();
            return row == null ? null : cast row.toObject();
        });
    }

    public static function forContent(id:Int):Array<TagRecord> {
        var contentRevision = ContentCache.revision("items");
        return ContentCache.remember("tags", "document", [id, contentRevision], () -> {
            var rows = Tag.query.select([
                "tags.id AS id",
                "tags.name AS name",
                "tags.slug AS slug",
                "tags.description AS description"
            ])
                .innerJoin("content_tags", "tags.id", "=", "content_tags.tag_id")
                .where("content_tags.content_id", id)
                .orderBy("tags.name_key")
                .limit(MAX_TAGS)
                .get();
            return [for (row in rows) (cast row.toObject() : TagRecord)];
        });
    }

    public static function parse(input:String):Null<Array<TagRecord>> {
        var identifiers:Array<String> = [];
        for (part in input.split(",")) {
            var value = StringTools.trim(part);
            if (value == "") {
                continue;
            }
            if (!~/^[1-9][0-9]*$/.match(value)) {
                return null;
            }
            if (!identifiers.contains(value)) {
                identifiers.push(value);
            }
        }
        if (identifiers.length > MAX_TAGS) {
            return null;
        }
        if (identifiers.length == 0) {
            return [];
        }
        var rows:Array<TagRecord> = [
            for (row in Tag.query.select(["id", "name", "slug", "description"])
                .whereIn("id", cast identifiers)
                .limit(MAX_TAGS)
                .get())
                (cast row.toObject() : TagRecord)
        ];
        return rows.length == identifiers.length ? rows : null;
    }

    public static function assign(contentId:Int, tags:Array<TagRecord>):Void {
        ContentTag.query.where("content_id", contentId).delete();
        for (tag in tags) {
            ContentTag.query.create(["content_id" => contentId, "tag_id" => tag.id]);
        }
    }
}
