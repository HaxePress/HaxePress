package extensions.cloudflare;

/** The visitor country Cloudflare sends in `CF-IPCountry`. **/
class CloudflareCountry {
    /**
        The country in `text` as two uppercase letters, or `null` when it is
        missing, malformed, unknown (`XX`) or Tor (`T1`, not letters).
    **/
    public static function normalize(text:Null<String>):Null<String> {
        if (text == null) {
            return null;
        }
        var code = StringTools.trim(text).toUpperCase();
        if (code.length != 2 || code == "XX") {
            return null;
        }
        for (index in 0...2) {
            var letter = StringTools.fastCodeAt(code, index);
            if (letter < "A".code || letter > "Z".code) {
                return null;
            }
        }
        return code;
    }
}
