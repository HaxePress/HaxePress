package hx.press.i18n;

import haxe.Json;
import hx.press.BuildIdentity;
import hx.press.ContentCache;
import hx.press.model.Setting;
import hx.press.packages.BuiltInTheme;
import hx.press.model.Translation;
import hx.press.model.TranslationText;
import hx.well.facades.DBStatic;

/** A text a package or the CMS ships, with the translations it ships for it. **/
typedef SyncedText = {
    var key:String;

    /** The source wording: text, or `{one, other}` for a plural text. **/
    var source:Dynamic;

    var origin:String;
    var audience:String;

    /** The shipped translations by language. **/
    var shipped:Map<String, Dynamic>;
}

private typedef StoredText = {
    var id:Int;
    var key_hash:String;
    var source:String;
    var plural:Int;
    var origin:String;
    var audience:String;
    var language:String;
    var unused:Int;
}

private typedef StoredTranslation = {
    var id:Int;
    var text_id:Int;
    var language:String;
    var value:String;
    var shipped:String;
}

/**
    Keeps the Translations page's texts in step with what the CMS, themes
    and plugins ship. Each namespace is reconciled as a whole: new texts are
    added, a changed source marks the site's translations for review, and a
    text a package no longer ships is removed unless the site translated
    it, in which case it is kept as unused. Shipped translations are copied
    into `translations.shipped` only, so the site's own translations
    survive every update.
**/
class TranslationSync {
    static inline var BATCH = 500;
    static inline var CORE_BUILD = "translation_core_build";

    /** Origins a package owns; texts the site or a plugin registered itself are left alone. **/
    static final packageOrigins = ["catalogue", "template", "manifest", "design"];

    public static function hash(key:String):String {
        return TextKeys.hash(key);
    }

    /** A message as it is stored: plural forms become a JSON object. **/
    public static function encode(message:Dynamic):String {
        if (message == null) {
            return "";
        }
        if (Std.isOfType(message, String)) {
            return message;
        }
        return Json.stringify({one: Std.string(message.one), other: Std.string(message.other)});
    }

    public static function isPlural(message:Dynamic):Bool {
        return message != null && !Std.isOfType(message, String);
    }

    /** The CMS's own texts, once for each build. **/
    public static function core(force:Bool = false):Void {
        if (!force
            && Setting.query.where("key", CORE_BUILD).where("value", BuildIdentity.id).exists()) {
            return;
        }
        reconcile("cms", I18n.FALLBACK, TranslationSources.core());
        reconcile(BuiltInTheme.ID, I18n.FALLBACK, TranslationSources.builtInTheme());
        Setting.query.upsert(["key" => CORE_BUILD, "value" => BuildIdentity.id], ["key"],
            ["value"]);
    }

    /** The texts of an installed theme or plugin. **/
    public static function forPackage(id:String):Void {
        var found = TranslationSources.forPackage(id);
        if (found == null) {
            forget(id);
            return;
        }
        reconcile(id, found.language, found.texts);
        // Core texts a theme shows are texts visitors see.
        var shown = TranslationSources.coreKeysOf(id);
        var index = 0;
        while (index < shown.length) {
            var hashes = [for (key in shown.slice(index, index + BATCH)) hash(key)];
            index += BATCH;
            TranslationText.query.where("namespace", "cms")
                .where(listed -> listed.whereIn("key_hash", cast hashes))
                .where("audience", "admin")
                .update(["audience" => "site"]);
        }
        if (shown.length > 0) {
            ContentCache.changed("translations");
        }
    }

    /**
        Lists the texts of a package after it is installed or updated. The
        package is already in place, so a failure is logged and Rescan on
        the Translations page lists its texts later.
    **/
    public static function afterInstall(id:String):Void {
        try {
            forPackage(id);
        } catch (error:Dynamic) {
            trace('The texts of ${id} could not be listed for translation: ${Std.string(error)}');
        }
    }

    /** Removes the texts of an uninstalled package and their translations. **/
    public static function forget(namespace:String):Void {
        var texts = TranslationText.query.select(["id"]).where("namespace", namespace);
        Translation.query.where(owned -> owned.whereInQuery("text_id", texts)).delete();
        TranslationText.query.where("namespace", namespace).delete();
        ContentCache.changed("translations");
    }

    static function storedTexts(namespace:String):Map<String, StoredText> {
        var stored:Map<String, StoredText> = [];
        var last = 0;
        while (true) {
            var rows = TranslationText.query.select(["id", "key_hash", "source", "plural", "origin", "audience", "language", "unused"])
                .where("namespace", namespace)
                .where("id", ">", last)
                .orderBy("id")
                .limit(BATCH)
                .get();
            for (row in rows) {
                var text:StoredText = cast row.toObject();
                stored.set(text.key_hash, text);
                last = text.id;
            }
            if (rows.length < BATCH) {
                return stored;
            }
        }
    }

    static function storedTranslations(namespace:String):Map<Int, Map<String, StoredTranslation>> {
        var stored:Map<Int, Map<String, StoredTranslation>> = [];
        var texts = TranslationText.query.select(["id"]).where("namespace", namespace);
        var last = 0;
        while (true) {
            var rows = Translation.query.select(["id", "text_id", "language", "value", "shipped"])
                .whereInQuery("text_id", texts)
                .where("id", ">", last)
                .orderBy("id")
                .limit(BATCH)
                .get();
            for (row in rows) {
                var translation:StoredTranslation = cast row.toObject();
                var languages = stored.get(translation.text_id);
                if (languages == null) {
                    languages = [];
                    stored.set(translation.text_id, languages);
                }
                languages.set(translation.language, translation);
                last = translation.id;
            }
            if (rows.length < BATCH) {
                return stored;
            }
        }
    }

    /**
        Makes the stored texts of `namespace` match `texts`, written in
        `language`. Texts a package owns and no longer ships are removed, or
        kept as unused while the site has translated them.
    **/
    public static function reconcile(namespace:String, language:String,
            texts:Array<SyncedText>):Void {
        var stored = storedTexts(namespace);
        var translations = storedTranslations(namespace);
        var now = Date.now().getTime() / 1000;
        var changed = false;
        DBStatic.transaction(() -> {
            var kept:Map<Int, Bool> = [];
            for (text in texts) {
                var keyHash = hash(text.key);
                var source = encode(text.source);
                var plural = isPlural(text.source) ? 1 : 0;
                var row = stored.get(keyHash);
                var id:Int;
                if (row == null) {
                    id = TranslationText.query.insert([
                        "namespace" => namespace,
                        "key" => text.key,
                        "key_hash" => keyHash,
                        "origin" => text.origin,
                        "audience" => text.audience,
                        "source" => source,
                        "plural" => plural,
                        "language" => language,
                        "unused" => 0,
                        "updated_epoch" => now
                    ]);
                    changed = true;
                } else {
                    id = row.id;
                    if (kept.exists(id)) {
                        continue;
                    }
                    var updates:Map<String, Dynamic> = [];
                    if (row.source != source || row.plural != plural) {
                        updates.set("source", source);
                        updates.set("plural", plural);
                        // Translations written for the old wording need a look.
                        Translation.query.where("text_id", id)
                            .where("value", "!=", "")
                            .update(["outdated" => 1]);
                    }
                    if (row.origin != text.origin) {
                        updates.set("origin", text.origin);
                    }
                    if (row.audience != text.audience) {
                        updates.set("audience", text.audience);
                    }
                    if (row.language != language) {
                        updates.set("language", language);
                    }
                    if (row.unused != 0) {
                        updates.set("unused", 0);
                    }
                    if (updates.keys().hasNext()) {
                        updates.set("updated_epoch", now);
                        TranslationText.query.where("id", id).update(updates);
                        changed = true;
                    }
                }
                kept.set(id, true);
                var current = translations.get(id) ?? new Map<String, StoredTranslation>();
                for (code => message in text.shipped) {
                    if (code == language) {
                        continue;
                    }
                    var shipped = encode(message);
                    var existing = current.get(code);
                    if (existing == null) {
                        Translation.query.insert([
                            "text_id" => id,
                            "language" => code,
                            "value" => "",
                            "shipped" => shipped,
                            "outdated" => 0,
                            "updated_by" => 0,
                            "updated_epoch" => now
                        ]);
                        changed = true;
                    } else if (existing.shipped != shipped) {
                        Translation.query.where("id", existing.id).update(["shipped" => shipped]);
                        changed = true;
                    }
                }
                for (code => existing in current) {
                    var stillShipped = code != language && text.shipped.exists(code);
                    if (existing.shipped == "" || stillShipped) {
                        continue;
                    }
                    if (existing.value == "") {
                        Translation.query.where("id", existing.id).delete();
                    } else {
                        Translation.query.where("id", existing.id).update(["shipped" => ""]);
                    }
                    changed = true;
                }
            }
            for (row in stored) {
                if (kept.exists(row.id) || !packageOrigins.contains(row.origin)) {
                    continue;
                }
                var current = translations.get(row.id);
                var translated = current != null
                    && Lambda.exists(current, translation -> translation.value != "");
                if (translated) {
                    if (row.unused == 0) {
                        TranslationText.query.where("id", row.id)
                            .update(["unused" => 1, "updated_epoch" => now]);
                    }
                    Translation.query.where("text_id", row.id)
                        .where("shipped", "!=", "")
                        .update(["shipped" => ""]);
                    Translation.query.where("text_id", row.id).where("value", "").delete();
                } else {
                    Translation.query.where("text_id", row.id).delete();
                    TranslationText.query.where("id", row.id).delete();
                }
                changed = true;
            }
        });
        if (changed) {
            ContentCache.changed("translations");
        }
    }
}
