package hx.press.view;

import wellout.render.Values;

/** Public custom field values prepared for display, like the former FieldValues component. */
class FieldDisplay {
    public static function values(definitions:Null<Array<Dynamic>>, values:Dynamic):Array<Dynamic> {
        var result:Array<Dynamic> = [];
        if (definitions == null || values == null) {
            return result;
        }
        for (definition in definitions) {
            if (definition.publicVisible != true) {
                continue;
            }
            var key:String = definition.key;
            var value:Dynamic = Values.field(values, key);
            if (value == null) {
                continue;
            }
            var kind:String = definition.kind;
            var text = Std.string(value);
            var image = "";
            if (kind == "image" && Std.isOfType(value, String)) {
                image = value;
            } else if (kind == "boolean") {
                text = value == true ? "Yes" : "No";
            } else if (kind == "select") {
                var options:Array<Dynamic> = definition.options;
                if (options != null) {
                    for (option in options) {
                        if (Values.equals(option.value, value)) {
                            text = option.label;
                        }
                    }
                }
            }
            result.push({
                key: key,
                label: definition.label,
                kind: kind,
                text: text,
                image: image
            });
        }
        return result;
    }
}
