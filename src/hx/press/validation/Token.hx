package hx.press.validation;

/**
    Random identifiers from `SecureToken.generate(32)`: 32 characters of
    letters, digits, `_` and `-`, such as session keys, upload keys and MCP
    link IDs.
**/
class Token {
    public static inline final LENGTH = 32;

    public static function valid(text:Null<String>):Bool {
        return text != null && text.length == LENGTH && ~/^[A-Za-z0-9_-]+(?![\s\S])/.match(text);
    }

    /** The token after `prefix` in `text`, such as `hxa_` in a bearer token, or null. **/
    public static function after(text:Null<String>, prefix:String):Null<String> {
        if (text == null || !StringTools.startsWith(text, prefix)) {
            return null;
        }
        var token = text.substr(prefix.length);
        return valid(token) ? token : null;
    }
}
