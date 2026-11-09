package hx.press.i18n;

import hx.press.ContentCache;
import hx.press.install.InstallationState;
import hx.press.model.Translation;
import hx.press.model.TranslationText;

/**
    The site's own texts on the Translations page, such as its name, menu
    labels and category names, in the `site` namespace. Each is keyed by the
    record it belongs to, such as `category.12.name`; the record keeps its
    source wording, which is edited on that record's page, and this class
    mirrors it so the page lists it in every language.
**/
class SiteTexts {
    public static inline var NAMESPACE = "site";

    /** More keys than one page shows. **/
    static inline var MAX_KEYS = 200;

    /** The admin page where the source wording of a site text is edited. **/
    public static function editPath(key:String):String {
        var kind = key.split(".")[0];
        return switch (kind) {
            case "setting": "/admin/settings";
            case "menu": "/admin/navigation";
            case "category": "/admin/categories";
            case "tag": "/admin/tags";
            case "collection": "/admin/collections";
            default: "/admin/translations";
        }
    }

    /**
        Lists or updates a site text with its source wording in the default
        language. An empty wording removes it. A wording that is also a CMS
        text, such as a seeded "Home" menu label, gets the CMS translations as
        its shipped ones.
    **/
    public static function put(key:String, origin:String, source:String):Void {
        if (InstallationState.pending) {
            return;
        }
        var text = StringTools.trim(source);
        if (text == "") {
            forget([key]);
            return;
        }
        var hash = TextKeys.hash(key);
        var now = Date.now().getTime() / 1000;
        var language = Languages.defaultCode();
        // Callers may already be inside a transaction, which cannot nest.
        var existing = TranslationText.query.select(["id", "source", "language"])
            .where("namespace", NAMESPACE)
            .where("key_hash", hash)
            .first();
        var id:Int;
        if (existing == null) {
            id = TranslationText.query.insert([
                "namespace" => NAMESPACE,
                "key" => key,
                "key_hash" => hash,
                "origin" => origin,
                "audience" => "site",
                "source" => text,
                "plural" => 0,
                "language" => language,
                "unused" => 0,
                "updated_epoch" => now
            ]);
        } else {
            id = existing.id;
            if (existing.source == text) {
                return;
            }
            TranslationText.query.where("id", id)
                .update(["source" => text, "updated_epoch" => now]);
            // Translations of the former wording need a look.
            Translation.query.where("text_id", id)
                .where("value", "!=", "")
                .update(["outdated" => 1]);
            Translation.query.where("text_id", id).where("value", "").delete();
            Translation.query.where("text_id", id).update(["shipped" => ""]);
        }
        for (code => messages in I18n.coreCatalogues()) {
            var message:Dynamic = messages.get(text);
            if (code == language || !Std.isOfType(message, String)) {
                continue;
            }
            Translation.query.upsert([
                "text_id" => id,
                "language" => code,
                "value" => "",
                "shipped" => message,
                "outdated" => 0,
                "updated_by" => 0,
                "updated_epoch" => now
            ], ["text_id", "language"], ["shipped"]);
        }
        ContentCache.changed("translations");
    }

    /** Removes site texts, such as those of a deleted category. **/
    public static function forget(keys:Array<String>):Void {
        if (InstallationState.pending || keys.length == 0) {
            return;
        }
        var hashes = [for (key in keys) TextKeys.hash(key)];
        var texts = TranslationText.query.select(["id"])
            .where("namespace", NAMESPACE)
            .where(listed -> listed.whereIn("key_hash", cast hashes));
        Translation.query.where(owned -> owned.whereInQuery("text_id", texts)).delete();
        TranslationText.query.where("namespace", NAMESPACE)
            .where(listed -> listed.whereIn("key_hash", cast hashes))
            .delete();
        ContentCache.changed("translations");
    }

    /**
        The translations of site texts into the page's language, by key. A
        key without one is missing from the map, so callers keep the source
        wording. A site with one language reads nothing.
    **/
    public static function texts(keys:Array<String>):Map<String, String> {
        var found:Map<String, String> = [];
        if (InstallationState.pending || !Languages.prefixed() || keys.length == 0) {
            return found;
        }
        var language = Languages.current();
        var listed = keys.slice(0, MAX_KEYS);
        listed.sort(Reflect.compare);
        var stored:Array<{key:String, value:String}> = ContentCache.remember("translations",
            "site-texts", [language, listed], () -> {
                var hashes = [for (key in listed) TextKeys.hash(key)];
                var rows = Translation.query.select([
                    "translation_texts.key AS key",
                    "translations.value AS value",
                    "translations.shipped AS shipped",
                    "translation_texts.language AS source_language"
                ])
                    .innerJoin("translation_texts", "translations.text_id", "=",
                        "translation_texts.id")
                    .where("translation_texts.namespace", NAMESPACE)
                    .where(matching -> matching.whereIn("translation_texts.key_hash", cast hashes))
                    .where("translations.language", language)
                    .limit(listed.length)
                    .get();
                var values:Array<{key:String, value:String}> = [];
                for (row in rows) {
                    var record:{
                        key:String,
                        value:String,
                        shipped:String
                    } = cast row.toObject();
                    var shown = record.value != "" ? record.value : record.shipped;
                    if (shown != "") {
                        values.push({key: record.key, value: shown});
                    }
                }
                return values;
            });
        for (entry in stored) {
            found.set(entry.key, entry.value);
        }
        return found;
    }

    /** One site text in the page's language, or its source wording. **/
    public static function text(key:String, source:String):String {
        if (!Languages.prefixed()) {
            return source;
        }
        return texts([key]).get(key) ?? source;
    }

    /** The settings visitors read, with the site texts in the page's language. **/
    public static function settings(stored:Map<String, String>):Map<String, String> {
        if (!Languages.prefixed()) {
            return stored;
        }
        var fields = ["site_name", "description", "about_site", "publisher_name"];
        var translated = texts([for (field in fields) 'setting.${field}']);
        if (!translated.keys().hasNext()) {
            return stored;
        }
        var localized = stored.copy();
        for (field in fields) {
            var value = translated.get('setting.${field}');
            if (value != null) {
                localized.set(field, value);
            }
        }
        return localized;
    }
}
