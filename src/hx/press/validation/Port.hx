package hx.press.validation;

/**
    TCP port numbers, from 1 to 65535, written as plain decimal digits.
    Request fields check them with the `cms.port` validator; settings read
    from `.env` use `parse` directly.
**/
class Port {
    public static inline final MIN = 1;
    public static inline final MAX = 65535;
    // 65535 has five digits; longer text cannot be a port, so it is not read further.
    static inline final MAX_DIGITS = 5;

    /** The port `text` names, or null when it is not 1–65535 in plain digits. **/
    public static function parse(text:Null<String>):Null<Int> {
        if (text == null || text.length == 0 || text.length > MAX_DIGITS) {
            return null;
        }
        var value = 0;
        for (index in 0...text.length) {
            var code = StringTools.fastCodeAt(text, index);
            if (code < "0".code || code > "9".code) {
                return null;
            }
            value = value * 10 + (code - "0".code);
        }
        return value >= MIN && value <= MAX ? value : null;
    }

    /** The port in the `.env` setting `key`, or an error that names the setting. **/
    public static function setting(key:String, text:Null<String>):Int {
        var port = parse(text);
        if (port == null) {
            throw '${key} must be a port number from ${MIN} to ${MAX}.';
        }
        return port;
    }
}
