package hx.press.i18n;

import hx.well.http.Request;

/** The `languages` root of public pages: the languages a visitor can switch to. **/
class LanguageChoices {
    /** The attribute a page sets to the address of the shown content in each language. **/
    public static inline var ALTERNATES = "hx.press.language.alternates";

    public static function forRequest(request:Null<Request>):Dynamic {
        var current = Languages.current();
        var choices:Array<Dynamic> = [];
        if (Languages.publicMultilingual()) {
            var alternates:Null<Map<String,
                String>> = request == null ? null : request.getAttribute(ALTERNATES, null);
            var path = request == null ? "/" : request.path;
            for (language in Languages.enabled()) {
                var neutral = alternates == null ? path : (alternates.get(language.code) ?? "/");
                choices.push({
                    code: language.code,
                    name: language.name,
                    direction: language.direction,
                    href: Languages.explicitPath(language.code, neutral),
                    current: language.code == current
                });
            }
        }
        return {
            multilingual: choices.length > 1,
            current: current,
            defaultLanguage: Languages.defaultCode(),
            choices: choices
        };
    }
}
