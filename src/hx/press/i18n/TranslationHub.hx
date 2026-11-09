package hx.press.i18n;

import haxe.Json;
import hx.press.ContentCache;
import hx.press.Pagination;
import hx.press.Pagination.PageCursor;
import hx.press.data.QueryPage;
import hx.press.model.InstalledPackage;
import hx.press.model.Translation;
import hx.press.model.TranslationText;
import hx.well.database.query.QueryBuilder;
import hx.well.facades.DBStatic;

using StringTools;

typedef HubFilter = {
    var language:String;

    /** `""` for every source, `core`, `site`, `themes`, `plugins` or a package id. **/
    var source:String;

    /** `all`, `missing`, `translated`, `edited`, `review` or `unused`. **/
    var status:String;

    /** `site` for texts visitors see, `admin` for the administration, `all` for both. **/
    var audience:String;

    var query:String;
}

typedef HubTextRow = {
    var id:Int;
    var namespace:String;
    var key:String;
    var origin:String;
    var audience:String;
    var source:String;
    var plural:Int;
    var language:String;
    var unused:Int;
}

typedef HubTranslationRow = {
    var text_id:Int;
    var language:String;
    var value:String;
    var shipped:String;
    var outdated:Int;
    var updated_epoch:Float;
}

typedef HubSaved = {
    var id:Int;
    var language:String;
    var status:String;
    var effective:String;
    var warnings:Array<String>;
}

/** The input of one translation: text, or both plural forms. **/
typedef HubInput = {
    var value:Null<String>;
    var one:Null<String>;
    var other:Null<String>;
}

/**
    The queries and writes of the Translations page and its MCP tools. Every
    list is filtered, counted and paged in SQL; a page reads the
    translations of its own rows only.
**/
class TranslationHub {
    public static inline var PAGE_SIZE = 50;
    public static inline var MAX_BATCH = 100;
    public static inline var MAX_VALUE = 4000;
    public static inline var EXPORT_PAGE = 500;
    public static final statuses = ["all", "missing", "translated", "edited", "review", "unused"];
    public static final audiences = ["site", "admin", "all"];

    static final textColumns = [
        "id",
        "namespace",
        "key",
        "origin",
        "audience",
        "source",
        "plural",
        "language",
        "unused"
    ];

    /** The languages translations are made for: every site language, public or not. **/
    public static function languages():Array<String> {
        return Languages.codes();
    }

    /** Installed themes and plugins, which are the package sources of texts. **/
    public static function packages():Array<{
        id:String,
        name:String,
        kind:String,
        enabled:Bool
    }> {
        return ContentCache.remember("translations", "sources",
            [ContentCache.revision("extensions")], () -> {
                var rows = InstalledPackage.query.select(["id", "name", "kind", "enabled"])
                    .orderBy("kind")
                    .orderBy("name")
                    .limit(200)
                    .get();
                return [
                    for (row in rows)
                        {
                            id: row.id,
                            name: row.name,
                            kind: row.kind,
                            enabled: row.enabled == 1
                        }
                ];
            });
    }

    public static function validSource(source:String):Bool {
        if (["", "core", "site", "themes", "plugins"].contains(source)) {
            return true;
        }
        return Lambda.exists(packages(), item -> item.id == source);
    }

    static function translated(language:String):QueryBuilder<Translation> {
        return Translation.query.select(["text_id"]).where("language", language);
    }

    /** The texts of a filter, before paging. **/
    static function filtered(filter:HubFilter):QueryBuilder<TranslationText> {
        var query = TranslationText.query.select(textColumns);
        switch (filter.source) {
            case "core":
                query.where("namespace", "cms");
            case "site":
                query.where("namespace", "site");
            case "themes" | "plugins":
                var kind = filter.source == "themes" ? "theme" : "plugin";
                query.whereInQuery("namespace",
                    InstalledPackage.query.select(["id"]).where("kind", kind));
            case "":
            default:
                query.where("namespace", filter.source);
        }
        if (filter.audience != "all") {
            query.where("audience", filter.audience);
        }
        query.where("unused", filter.status == "unused" ? 1 : 0);
        switch (filter.status) {
            case "missing":
                query.where("language", "!=", filter.language)
                    .whereNotInQuery("id", translated(filter.language));
            case "translated":
                query.whereInQuery("id", translated(filter.language));
            case "edited":
                query.whereInQuery("id", translated(filter.language).where("value", "!=", ""));
            case "review":
                query.whereInQuery("id", translated(filter.language).where("outdated", 1));
            default:
        }
        var search = filter.query.trim();
        if (search != "") {
            var pattern = '%${escapeLike(search)}%';
            query.where(match -> match.whereLike("source", pattern).orWhereLike("key", pattern));
        }
        return query;
    }

    static function escapeLike(text:String):String {
        return text.replace("!", "!!").replace("%", "!%").replace("_", "!_");
    }

    static function filterKey(filter:HubFilter):Array<Dynamic> {
        return [filter.language, filter.source, filter.status, filter.audience, filter.query];
    }

    public static function page(filter:HubFilter, cursor:Null<PageCursor>):QueryPage<HubTextRow> {
        return ContentCache.remember("translations", "page",
            filterKey(filter).concat([Pagination.token(cursor), PAGE_SIZE]), () -> {
                var query = filtered(filter);
                if (cursor != null) {
                    query.where("id", cursor.before ? "<" : ">", cursor.id);
                }
                var direction = cursor != null && cursor.before ? "DESC" : "ASC";
                var rows:Array<HubTextRow> = [
                    for (row in query.orderBy("id", direction).limit(PAGE_SIZE + 1).get())
                        (cast row.toObject() : HubTextRow)
                ];
                return Pagination.slice(rows, PAGE_SIZE, cursor);
            });
    }

    public static function count(filter:HubFilter):Int {
        return ContentCache.remember("translations", "count", filterKey(filter),
            () -> filtered(filter).count());
    }

    /** How many texts of a source and audience a language has, and how many it translates. **/
    public static function progress(language:String, source:String, audience:String):{
        total:Int,
        translated:Int,
        edited:Int,
        review:Int
    } {
        var filter = (status:String) -> ({
            language: language,
            source: source,
            status: status,
            audience: audience,
            query: ""
        } : HubFilter);
        var total = count(filter("all"));
        var missing = count(filter("missing"));
        return {
            total: total,
            translated: total - missing,
            edited: count(filter("edited")),
            review: count(filter("review"))
        };
    }

    /** The translations into `language` of the listed texts. **/
    public static function translationsOf(ids:Array<Int>,
            language:String):Map<Int, HubTranslationRow> {
        var found:Map<Int, HubTranslationRow> = [];
        if (ids.length == 0) {
            return found;
        }
        var rows = Translation.query.select(["text_id", "language", "value", "shipped", "outdated", "updated_epoch"])
            .where(owned -> owned.whereIn("text_id", cast ids))
            .where("language", language)
            .limit(ids.length)
            .get();
        for (row in rows) {
            var translation:HubTranslationRow = cast row.toObject();
            found.set(translation.text_id, translation);
        }
        return found;
    }

    /** Every translation of one text, bounded by the site's languages. **/
    public static function allTranslations(id:Int):Array<HubTranslationRow> {
        var rows = Translation.query.select(["text_id", "language", "value", "shipped", "outdated", "updated_epoch"])
            .where("text_id", id)
            .orderBy("language")
            .limit(Languages.MAX_LANGUAGES * 4)
            .get();
        return [for (row in rows) (cast row.toObject() : HubTranslationRow)];
    }

    public static function text(id:Int):Null<HubTextRow> {
        var row = TranslationText.query.select(textColumns).where("id", id).limit(1).first();
        return row == null ? null : cast row.toObject();
    }

    public static function texts(ids:Array<Int>):Map<Int, HubTextRow> {
        var found:Map<Int, HubTextRow> = [];
        if (ids.length == 0) {
            return found;
        }
        var rows = TranslationText.query.select(textColumns)
            .where(listed -> listed.whereIn("id", cast ids))
            .limit(ids.length)
            .get();
        for (row in rows) {
            var text:HubTextRow = cast row.toObject();
            found.set(text.id, text);
        }
        return found;
    }

    /** The status of a text in a language. **/
    public static function status(text:HubTextRow, translation:Null<HubTranslationRow>,
            language:String):String {
        if (text.unused == 1) {
            return "unused";
        }
        if (translation != null && translation.value != "") {
            return translation.outdated == 1 ? "review" : "edited";
        }
        if (translation != null && translation.shipped != "") {
            return "translated";
        }
        return text.language == language ? "source" : "missing";
    }

    /** The text a language shows: the site's translation, the shipped one or the source. **/
    public static function effective(text:HubTextRow, translation:Null<HubTranslationRow>):String {
        if (translation != null && translation.value != "") {
            return translation.value;
        }
        if (translation != null && translation.shipped != "") {
            return translation.shipped;
        }
        return text.source;
    }

    /** The placeholders such as `{name}` of a message, in order and without repeats. **/
    public static function placeholders(message:String):Array<String> {
        var pattern = ~/\{([a-zA-Z][a-zA-Z0-9_]*)\}/g;
        var names:Array<String> = [];
        var rest = message;
        while (pattern.match(rest)) {
            var name = pattern.matched(1);
            if (!names.contains(name)) {
                names.push(name);
            }
            rest = pattern.matchedRight();
        }
        return names;
    }

    /** The forms of a stored message: one text, or the plural forms. **/
    public static function forms(text:HubTextRow, stored:String):Array<String> {
        if (text.plural != 1 || stored == "") {
            return [stored];
        }
        try {
            var parsed:Dynamic = Json.parse(stored);
            return [Std.string(parsed.one), Std.string(parsed.other)];
        } catch (error:Dynamic) {
            return [stored];
        }
    }

    static function normalize(value:Null<String>):String {
        return value == null ? "" : value.replace("\r\n", "\n");
    }

    /**
        Checks a translation of `text` into `language`. Returns the error, or
        null with the stored value and the source placeholders it leaves out.
    **/
    public static function validate(text:HubTextRow, language:String,
            input:HubInput):{error:Null<String>, value:String, warnings:Array<String>} {
        var fail = (message:String) -> ({error: message, value: "", warnings: []});
        if (!languages().contains(language)) {
            return fail("Choose one of the site’s languages.");
        }
        if (text.namespace == "site" && text.language == language) {
            return fail("Edit this text on its own page; this is its source language.");
        }
        var known = placeholders(text.source);
        var parts:Array<String>;
        var value:String;
        if (text.plural == 1) {
            var one = normalize(input.one).trim();
            var other = normalize(input.other).trim();
            if (one == "" || other == "" || (input.value != null && input.value != "")) {
                return fail("Plural texts need both one and other forms.");
            }
            parts = [one, other];
            value = Json.stringify({one: one, other: other});
        } else {
            var single = normalize(input.value);
            if (single.trim() == "" || input.one != null || input.other != null) {
                return fail("Enter the translation.");
            }
            parts = [single];
            value = single;
        }
        for (part in parts) {
            if (part.length > MAX_VALUE) {
                return fail("A translation can contain at most 4000 characters.");
            }
            for (name in placeholders(part)) {
                if (!known.contains(name)) {
                    var allowed = [for (placeholder in known) '{${placeholder}}'].join(", ");
                    var listed = allowed == "" ? "none" : allowed;
                    return fail('Use only the placeholders of the source text: ${listed}.');
                }
            }
        }
        var used = placeholders(parts.join("\n"));
        var warnings = known.filter(name -> !used.contains(name));
        return {error: null, value: value, warnings: warnings};
    }

    /** Saves a validated translation, keeping the shipped one it overrides. **/
    public static function write(text:HubTextRow, language:String, value:String, adminId:Int):Void {
        Translation.query.upsert([
            "text_id" => text.id,
            "language" => language,
            "value" => value,
            "shipped" => "",
            "outdated" => 0,
            "updated_by" => adminId,
            "updated_epoch" => Date.now().getTime() / 1000
        ],
            ["text_id", "language"], ["value", "outdated", "updated_by", "updated_epoch"]);
    }

    public static function save(text:HubTextRow, language:String, input:HubInput,
            adminId:Int):{error:Null<String>, saved:Null<HubSaved>} {
        var checked = validate(text, language, input);
        if (checked.error != null) {
            return {error: checked.error, saved: null};
        }
        DBStatic.transaction(() -> write(text, language, checked.value, adminId));
        ContentCache.changed("translations");
        return {error: null, saved: savedState(text, language, checked.warnings)};
    }

    static function savedState(text:HubTextRow, language:String, warnings:Array<String>):HubSaved {
        var translation = translationsOf([text.id], language).get(text.id);
        return {
            id: text.id,
            language: language,
            status: status(text, translation, language),
            effective: effective(text, translation),
            warnings: warnings
        };
    }

    /** Removes the site's translation; a shipped translation applies again. **/
    public static function remove(text:HubTextRow, language:String):HubSaved {
        DBStatic.transaction(() -> {
            Translation.query.where("text_id", text.id)
                .where("language", language)
                .where("shipped", "")
                .delete();
            Translation.query.where("text_id", text.id)
                .where("language", language)
                .update(["value" => "", "outdated" => 0]);
        });
        ContentCache.changed("translations");
        return savedState(text, language, []);
    }

    /**
        Saves several translations into one language. Valid items are saved
        together; each invalid one is reported, so one mistake does not undo
        a translated page.
    **/
    public static function saveMany(language:String, items:Array<{id:Int, input:HubInput}>,
            adminId:Int):{saved:Array<HubSaved>, failed:Array<{id:Int, error:String}>} {
        var found = texts([for (item in items) item.id]);
        var valid:Array<{text:HubTextRow, value:String, warnings:Array<String>}> = [];
        var failed:Array<{id:Int, error:String}> = [];
        for (item in items) {
            var text = found.get(item.id);
            if (text == null) {
                failed.push({id: item.id, error: "This text does not exist."});
                continue;
            }
            var checked = validate(text, language, item.input);
            if (checked.error != null) {
                failed.push({id: item.id, error: checked.error});
            } else {
                valid.push({text: text, value: checked.value, warnings: checked.warnings});
            }
        }
        if (valid.length > 0) {
            DBStatic.transaction(() -> {
                for (entry in valid) {
                    write(entry.text, language, entry.value, adminId);
                }
            });
            ContentCache.changed("translations");
        }
        var states = translationsOf([for (entry in valid) entry.text.id], language);
        var saved = [
            for (entry in valid)
                {
                    id: entry.text.id,
                    language: language,
                    status: status(entry.text, states.get(entry.text.id), language),
                    effective: effective(entry.text, states.get(entry.text.id)),
                    warnings: entry.warnings
                }
        ];
        return {saved: saved, failed: failed};
    }

    /**
        A page of one namespace's messages in a language, in the package
        catalogue format: `effective` exports what the language shows,
        `site` only the site's translations and `missing` the source texts
        that still need one.
    **/
    public static function exportPage(namespace:String, language:String, include:String,
            after:Int):{
        messages:Map<String, Dynamic>,
        next:Int
    } {
        var query = TranslationText.query.select(textColumns)
            .where("namespace", namespace)
            .where("unused", 0)
            .where("id", ">", after);
        switch (include) {
            case "site":
                query.whereInQuery("id", translated(language).where("value", "!=", ""));
            case "missing":
                query.where("language", "!=", language).whereNotInQuery("id", translated(language));
            default:
        }
        var rows:Array<HubTextRow> = [
            for (row in query.orderBy("id").limit(EXPORT_PAGE + 1).get())
                (cast row.toObject() : HubTextRow)
        ];
        var more = rows.length > EXPORT_PAGE;
        rows = rows.slice(0, EXPORT_PAGE);
        var states = translationsOf([for (row in rows) row.id], language);
        var messages:Map<String, Dynamic> = [];
        for (row in rows) {
            var translation = states.get(row.id);
            var stored = include == "site" ? translation.value : include == "missing" ? row.source : effective(row,
                translation);
            messages.set(row.key, row.plural == 1 ? Json.parse(stored) : stored);
        }
        return {messages: messages, next: more ? rows[rows.length - 1].id : 0};
    }

    /** Finds the texts of a namespace by key, in batches. **/
    public static function byKeys(namespace:String, keys:Array<String>):Map<String, HubTextRow> {
        var found:Map<String, HubTextRow> = [];
        var index = 0;
        while (index < keys.length) {
            var batch = keys.slice(index, index + EXPORT_PAGE);
            index += EXPORT_PAGE;
            var hashes = [for (key in batch) TextKeys.hash(key)];
            var rows = TranslationText.query.select(textColumns)
                .where("namespace", namespace)
                .where(listed -> listed.whereIn("key_hash", cast hashes))
                .limit(batch.length)
                .get();
            for (row in rows) {
                var text:HubTextRow = cast row.toObject();
                found.set(text.key, text);
            }
        }
        return found;
    }
}
