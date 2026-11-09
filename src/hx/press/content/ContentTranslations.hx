package hx.press.content;

import hx.press.ContentCache;
import hx.press.i18n.Languages;
import hx.press.model.ContentItem;
import hx.well.internal.SecureToken;
import hx.well.database.query.QueryBuilder;

typedef TranslationEntry = {
    var id:Int;
    var language:String;
    var title:String;
    var slug:String;
    var status:String;
    var content_type:String;
}

/**
    Translations of content. Each translation is its own item with its own
    language and slug; items that translate each other share a
    `translation_group`, which an item gets with its first translation. An
    item marked for every language (`all_languages`) also appears in the
    languages its group has no published item in, so an item is never
    listed twice.
**/
class ContentTranslations {
    /** The most items one group can hold: one in each language. **/
    static inline var MAX_GROUP = 64;

    /** The groups that have a published item in `language`. **/
    static function present(language:String, kind:String):QueryBuilder<ContentItem> {
        var groups = ContentItem.query.select(["translation_group"])
            .where("language", language)
            .where("status", "published")
            .where("translation_group", "!=", "");
        if (kind != "") {
            groups.where("content_type", kind);
        }
        return groups;
    }

    /**
        Limits `query` to the items visitors see in `language`: its own items,
        and items shown in every language whose group has no published item
        in it. A site with one language has no condition.
    **/
    public static function visibleIn(query:QueryBuilder<ContentItem>, kind:String,
            language:String):Void {
        if (!Languages.prefixed()) {
            return;
        }
        var groups = present(language, kind);
        var hidden = [for (record in Languages.all()) if (record.enabled != 1) record.code];
        query.where(visible -> {
            visible.where("content_items.language", language).orWhere(shared -> {
                shared.where("content_items.all_languages", 1)
                    .where("content_items.language", "!=", language)
                    .whereNotInQuery("content_items.translation_group", groups);
                // Items of a disabled language are not shown anywhere.
                if (hidden.length > 0) {
                    shared.whereNotIn("content_items.language", cast hidden);
                }
            });
        });
    }

    /** A new group for an item's first translation. **/
    public static function newGroup():String {
        return SecureToken.generate(16);
    }

    /** The items of a group, every status but the trash. **/
    public static function group(group:String, kind:String):Array<TranslationEntry> {
        if (group == "") {
            return [];
        }
        var rows = ContentItem.query.select(["id", "language", "title", "slug", "status", "content_type"])
            .where("translation_group", group)
            .where("content_type", kind)
            .where("status", "!=", "trash")
            .orderBy("language")
            .limit(MAX_GROUP)
            .get();
        return [for (row in rows) (cast row.toObject() : TranslationEntry)];
    }

    /** The published items of a group, which pages link as their alternates. **/
    public static function published(group:String, kind:String):Array<TranslationEntry> {
        if (group == "" || !Languages.prefixed()) {
            return [];
        }
        return ContentCache.remember("items", "translations", [group, kind], () -> {
            var rows = ContentItem.query.select(["id", "language", "title", "slug", "status", "content_type"])
                .where("translation_group", group)
                .where("content_type", kind)
                .where("status", "published")
                .orderBy("language")
                .limit(MAX_GROUP)
                .get();
            return [for (row in rows) (cast row.toObject() : TranslationEntry)];
        });
    }
}
