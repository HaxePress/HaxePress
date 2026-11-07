package hx.press.validation;

import haxe.io.Bytes;
import hx.well.facades.Validator;

class CmsValidators {
    public static function register():Void {
        Validator.extend("cms.byte_length", (_, value, parameters) -> {
            return Std.isOfType(value, String) && parameters.length == 1
                && Bytes.ofString(value).length <= Std.int(parameters[0]);
        });
        // A TCP port from 1 to 65535 in plain digits, such as a database port.
        Validator.extend("cms.port", (_, value, _) -> {
            return Std.isOfType(value, String) && Port.parse(value) != null;
        });
        // A whole number from 1 to an optional maximum, such as a record ID or a version.
        Validator.extend("cms.positive_int", (_, value, parameters) -> {
            var max = parameters != null
                && parameters.length == 1 ? Std.int(parameters[0]) : PositiveInt.MAX;
            return Std.isOfType(value, String) && PositiveInt.parse(value, max) != null;
        });
        // Text without control characters, such as a name, an email address or a password.
        Validator.extend("cms.line", (_, value, _) -> {
            return Std.isOfType(value, String) && TextLine.valid(value);
        });
        // A 32-character random identifier, such as an upload key.
        Validator.extend("cms.token", (_, value, _) -> {
            return Std.isOfType(value, String) && Token.valid(value);
        });
        // Lowercase words joined by hyphens, such as a content slug.
        Validator.extend("cms.slug", (_, value, _) -> {
            return Std.isOfType(value, String) && Slug.valid(value);
        });
        // A checkbox value: "0" or "1".
        Validator.extend("cms.flag", (_, value, _) -> Flag.valid(value));
    }
}
