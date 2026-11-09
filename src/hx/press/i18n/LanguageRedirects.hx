package hx.press.i18n;

import hx.press.content.ContentTypes;
import hx.press.model.ContentItem;

/** Where a visitor goes when they ask for a disabled language. **/
class LanguageRedirects {
    /**
        The address of `path`, requested in the disabled `language`, in the
        default language: the same content when it is published there,
        otherwise the homepage.
    **/
    public static function disabled(path:String, language:String):String {
        var parts = path.split("?")[0].split("/");
        if (parts.length != 3 || parts[2] == "") {
            return "/";
        }
        var type = ContentTypes.byPath(parts[1]);
        if (type == null) {
            return "/";
        }
        var groups = ContentItem.query.select(["translation_group"])
            .where("content_type", type.key)
            .where("language", language)
            .where("slug", StringTools.urlDecode(parts[2]))
            .where("translation_group", "!=", "");
        var original = ContentItem.query.select(["slug"])
            .where("content_type", type.key)
            .where("language", Languages.defaultCode())
            .where("status", "published")
            .whereInQuery("translation_group", groups)
            .first();
        return
            original == null ? "/" : '${type.publicBase}/${StringTools.urlEncode(original.slug)}';
    }
}
