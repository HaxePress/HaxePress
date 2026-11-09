package hx.press.i18n;

import haxe.Json;
import hx.press.ContentCache;
import hx.press.install.InstallationState;
import hx.press.model.Translation;

/**
    The translations made on this site for one namespace and language, as
    catalogue messages. `I18n` merges them over the shipped catalogues once
    per revision, so pages never query single texts.
**/
class TranslationOverrides {
    /** More than any catalogue holds; a namespace's texts are bounded by its catalogues and pages. **/
    static inline var MAX_TEXTS = 10000;

    static final none:Map<String, Dynamic> = [];

    public static function forLanguage(namespace:String, language:String):Map<String, Dynamic> {
        if (InstallationState.pending) {
            return none;
        }
        return ContentCache.remember("translations", "overrides", [namespace, language], () -> {
            var rows = Translation.query.select([
                "translation_texts.key AS key",
                "translation_texts.plural AS plural",
                "translations.value AS value"
            ])
                .innerJoin("translation_texts", "translations.text_id", "=", "translation_texts.id")
                .where("translation_texts.namespace", namespace)
                .where("translations.language", language)
                .where("translations.value", "!=", "")
                .orderBy("translations.id")
                .limit(MAX_TEXTS)
                .get();
            var messages:Map<String, Dynamic> = [];
            for (row in rows) {
                var record:{key:String, plural:Int, value:String} = cast row.toObject();
                messages.set(record.key,
                    record.plural == 1 ? Json.parse(record.value) : record.value);
            }
            return messages;
        });
    }
}
