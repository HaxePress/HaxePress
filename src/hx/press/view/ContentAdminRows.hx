package hx.press.view;

import hx.press.content.ContentTypeDefinition;
import hx.press.content.ContentTypeDefinition.ContentFieldDefinition;

typedef ContentAdminColumn = {
    var text:String;
    var translate:Bool;
}

/** The custom fields a collection shows as list columns, and their cell texts. **/
class ContentAdminRows {
    public static function listFields(type:ContentTypeDefinition):Array<ContentFieldDefinition> {
        return [for (field in type.fields) if (field.inList) field];
    }

    /** The text of a custom field's list cell. **/
    public static function column(field:ContentFieldDefinition, value:Dynamic):ContentAdminColumn {
        if (value == null) {
            return {text: "—", translate: false};
        }
        return switch (field.kind) {
            case "boolean":
                {text: value == true ? "Yes" : "No", translate: true};
            case "select":
                {text: optionLabel(field, Std.string(value)), translate: false};
            default:
                {text: Std.string(value), translate: false};
        }
    }

    static function optionLabel(field:ContentFieldDefinition, value:String):String {
        for (option in field.options) {
            if (option.value == value && option.label != "") {
                return option.label;
            }
        }
        return value;
    }
}
