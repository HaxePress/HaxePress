package hx.press.validation;

/**
    URL slugs and keys: lowercase letters and digits in words joined by
    single hyphens, such as `my-first-post`. Callers limit the length.
**/
class Slug {
    public static function valid(text:Null<String>):Bool {
        return text != null && ~/^[a-z0-9]+(-[a-z0-9]+)*(?![\s\S])/.match(text);
    }

    /** Whether `text` is `prefix` followed by a slug, such as `theme-simple`. **/
    public static function prefixed(text:Null<String>, prefix:String):Bool {
        return text != null && StringTools.startsWith(text, prefix)
            && valid(text.substr(prefix.length));
    }
}
