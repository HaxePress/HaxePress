package hx.press.i18n;

import haxe.Exception;
import haxe.Json;

/** Plain JSON messages shared by Haxe, React and browser extensions. */
class TranslationCatalogue {
    public static inline var MAX_BYTES = 128 * 1024;
    public static inline var MAX_MESSAGES = 1500;

    /** Parses an uploaded package's catalogue within the size and message limits. **/
    public static function parse(source:String):Map<String, Dynamic> {
        if (source.length > MAX_BYTES) {
            throw new Exception("A translation catalogue must be smaller than 128 KB.");
        }
        return read(source, true);
    }

    /**
        Parses a catalogue that is part of the application build, such as the
        core catalogues. Its shape is checked, but not its size: the limits
        protect the site from uploaded packages.
    **/
    public static function parseTrusted(source:String):Map<String, Dynamic> {
        return read(source, false);
    }

    static function read(source:String, limited:Bool):Map<String, Dynamic> {
        var input:Dynamic = Json.parse(source);
        if (input == null
            || !Reflect.isObject(input)
            || Std.isOfType(input, Array)
            || Std.isOfType(input, String)) {
            throw new Exception("Translation catalogues must contain a JSON object.");
        }
        var keys = Reflect.fields(input);
        if (limited && keys.length > MAX_MESSAGES) {
            throw new Exception("A translation catalogue can contain at most 1500 messages.");
        }
        var messages:Map<String, Dynamic> = [];
        for (key in keys) {
            if (key.length == 0 || key.length > 500 || ~/[\x00-\x1f]/.match(key)) {
                throw new Exception("Translation message keys have an invalid length or character.");
            }
            var value:Dynamic = Reflect.field(input, key);
            if (Std.isOfType(value, String)) {
                validateText(value);
            } else {
                if (value == null || !Reflect.isObject(value) || Std.isOfType(value, Array)) {
                    throw new Exception("A translation must be text or contain one/other plural forms.");
                }
                var forms = Reflect.fields(value);
                if (forms.length != 2 || !forms.contains("one") || !forms.contains("other")) {
                    throw new Exception("Plural translations require exactly one and other forms.");
                }
                validateText(value.one);
                validateText(value.other);
            }
            messages.set(key, value);
        }
        return messages;
    }

    static function validateText(value:Dynamic):Void {
        if (!Std.isOfType(value, String) || value.length > 4000) {
            throw new Exception("Translation values must contain at most 4000 characters.");
        }
    }

    public static function format(message:Dynamic, key:String,
            parameters:Map<String, Dynamic>):String {
        var text:String;
        if (message == null) {
            text = key;
        } else if (Std.isOfType(message, String)) {
            text = message;
        } else {
            var count:Dynamic = parameters == null ? null : parameters.get("count");
            text = count == 1 ? message.one : message.other;
        }
        if (parameters != null) {
            var placeholders = ~/\{([a-zA-Z][a-zA-Z0-9_]*)\}/g;
            text = placeholders.map(text, match -> {
                var name = match.matched(1);
                return
                    parameters.exists(name) ? Std.string(parameters.get(name)) : match.matched(0);
            });
        }
        return text;
    }
}
