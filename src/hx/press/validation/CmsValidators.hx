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
    }
}
