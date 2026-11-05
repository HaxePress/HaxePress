package hx.press.validation;

import haxe.io.Bytes;
import hx.well.facades.Validator;

class CmsValidators {
    public static function register():Void {
        Validator.extend("cms.byte_length", (_, value, parameters) -> {
            return Std.isOfType(value, String) && parameters.length == 1
                && Bytes.ofString(value).length <= Std.int(parameters[0]);
        });
    }
}
