package hx.press.validation;

/**
    Text that stays on one line: no control characters (U+0000 to U+001F
    and U+007F), such as names, email addresses, passwords and keys that
    are written into `.env`, headers or file names.
**/
class TextLine {
    public static function valid(text:Null<String>):Bool {
        return text != null && !hasControl(text);
    }

    /** Whether `text` contains a control character, such as a line break or a tab. **/
    public static function hasControl(text:String):Bool {
        return ~/[\x00-\x1f\x7f]/.match(text);
    }
}
