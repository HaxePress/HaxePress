package hx.press.content;

import hx.press.data.ContentItemRecord;
import hx.press.i18n.Languages;

/**
    Where the language switcher of a content page leads in each public
    language: the item's translation, the item itself where it is shown in
    every language, or that language's homepage.
**/
class ContentAlternates {
    public static function of(item:ContentItemRecord, type:ContentTypeDefinition,
            home:Bool):Map<String, String> {
        var paths:Map<String, String> = [];
        if (!Languages.publicMultilingual()) {
            return paths;
        }
        var own = '${type.publicBase}/${StringTools.urlEncode(item.slug)}';
        var translated:Map<String, String> = [];
        for (entry in ContentTranslations.published(item.translation_group, type.key)) {
            translated.set(entry.language,
                '${type.publicBase}/${StringTools.urlEncode(entry.slug)}');
        }
        for (language in Languages.enabled()) {
            var code = language.code;
            if (home) {
                paths.set(code, "/");
            } else if (code == item.language) {
                paths.set(code, own);
            } else if (translated.exists(code)) {
                paths.set(code, translated.get(code));
            } else if (item.all_languages == 1) {
                paths.set(code, own);
            } else {
                paths.set(code, "/");
            }
        }
        return paths;
    }
}
