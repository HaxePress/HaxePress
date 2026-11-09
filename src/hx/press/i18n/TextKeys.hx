package hx.press.i18n;

import haxe.crypto.Md5;

/**
    How the Translations page identifies a text within its namespace: by
    the MD5 of its key, so MySQL's case-insensitive collations and index
    length limits treat every key alike.
**/
class TextKeys {
    public static function hash(key:String):String {
        return Md5.encode(key);
    }
}
