package hx.press.view;

import hx.press.content.ContentTypeDefinition;
import hx.press.content.ContentTypeDefinition.ContentFieldDefinition;

typedef ContentAdminColumn = {
    var text:String;
    var translate:Bool;
}

/**
    Content table rows for the admin collection lists: the custom fields a
    collection shows as columns and their cell texts, prepared like the
    former `ContentTable` component did in the browser.
**/
class ContentAdminRows {
    public static function listFields(type:ContentTypeDefinition):Array<ContentFieldDefinition> {
        return [for (field in type.fields) if (field.inList) field];
    }

    /** Adds the column texts of `fields` to an admin content summary as `columns`. **/
    public static function withColumns(summary:Dynamic,
            fields:Array<ContentFieldDefinition>):Dynamic {
        var values:Dynamic = summary.fields;
        var columns = [
            for (field in fields)
                column(field, values == null ? null : Reflect.field(values, field.key))
        ];
        summary.columns = columns;
        return summary;
    }

    static function column(field:ContentFieldDefinition, value:Dynamic):ContentAdminColumn {
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
