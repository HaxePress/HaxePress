package hx.press.content;

import haxe.Exception;
import haxe.Json;
import hx.press.ContentCache;
import hx.press.media.MediaReferences;
import hx.press.media.MediaLocks;
import hx.press.content.ContentTypeDefinition.ContentFieldDefinition;
import hx.press.model.ContentItem;
import hx.press.model.ContentValue;
import hx.well.database.query.QueryBuilder;
import hx.well.http.Request;

typedef ContentValueRecord = {
    var field_key:String;
    var value:String;
}

typedef ContentFieldFilter = {
    var key:String;
    var value:Dynamic;
    var number:Bool;
}

/** Bounded custom values stay out of list projections and participate in native queries. */
class ContentFields {
    static function alias(key:String):String {
        return '__cms_field_${key}';
    }

    public static function projectList(query:QueryBuilder<ContentItem>,
            type:ContentTypeDefinition, publicOnly:Bool):Void {
        for (field in type.fields) {
            if (field.inList && (!publicOnly || field.publicVisible)) {
                var value = ContentValue.query.select(["value"])
                    .whereColumn("content_values.content_id", "content_items.id")
                    .where("field_key", field.key)
                    .limit(1);
                query.selectSub(value, alias(field.key));
            }
        }
    }

    public static function listValues(record:Dynamic, type:ContentTypeDefinition,
            publicOnly:Bool):Dynamic {
        var values:Dynamic = {};
        for (field in type.fields) {
            if (field.inList && (!publicOnly || field.publicVisible)) {
                var encoded:String = Reflect.field(record, alias(field.key));
                if (encoded != null) {
                    var value:Dynamic = Json.parse(encoded);
                    if (publicOnly) {
                        try {
                            value = validateValue(field, value);
                        } catch (_:Dynamic) {
                            value = null;
                        }
                    }
                    Reflect.setField(values, field.key, value);
                }
            }
        }
        return values;
    }

    public static function clearListAliases(record:Dynamic):Void {
        for (key in Reflect.fields(record)) {
            // Custom fields, plugin columns and sort values the list query selected.
            if (StringTools.startsWith(key, "__cms_")) {
                Reflect.deleteField(record, key);
            }
        }
    }

    public static function values(id:Int, type:ContentTypeDefinition, publicOnly:Bool = false,
            cached:Bool = true):Dynamic {
        var keys = [for (field in type.fields) if (!publicOnly || field.publicVisible) field.key];
        if (id == 0 || keys.length == 0) {
            return {};
        }
        var load = () -> {
            return ContentValue.query.select(["field_key", "value"])
                .where("content_id", id)
                .whereIn("field_key", cast keys)
                .limit(ContentTypes.MAX_FIELDS)
                .get()
                .map(model -> cast model.toObject());
        };
        var rows:Array<ContentValueRecord> = cached ? ContentCache.remember("items",
            "custom-values", [id, type.key, keys], load) : load();
        var result:Dynamic = {};
        for (row in rows) {
            var value:Dynamic = Json.parse(row.value);
            if (publicOnly) {
                for (field in type.fields) {
                    if (field.key == row.field_key) {
                        try {
                            value = validateValue(field, value);
                        } catch (_:Dynamic) {
                            value = null;
                        }
                        break;
                    }
                }
            }
            Reflect.setField(result, row.field_key, value);
        }
        return result;
    }

    public static function decode(input:Dynamic, fallback:Dynamic = null):Dynamic {
        if (input == null) {
            return fallback ?? {};
        }
        var result:Dynamic = input;
        if (input is String) {
            if (input.length > 64000) {
                throw new Exception("Custom field values exceed the editor limit.");
            }
            try {
                result = Json.parse(input);
            } catch (_:Dynamic) {
                throw new Exception("Custom field values must contain a valid object.");
            }
        }
        if (result == null
            || !Reflect.isObject(result)
            || (result is Array)
            || (result is String)) {
            throw new Exception("Custom field values must contain an object.");
        }
        if (Reflect.fields(result).length > ContentTypes.MAX_FIELDS
            || Json.stringify(result).length > 64000) {
            throw new Exception("Custom field values exceed the editor limit.");
        }
        return result;
    }

    static function validateValue(field:ContentFieldDefinition, value:Dynamic):Dynamic {
        if (value == null || value == "") {
            return null;
        }
        switch (field.kind) {
            case "boolean":
                if (!Std.isOfType(value, Bool)) {
                    throw new Exception('Choose a valid boolean value for ${field.label}.');
                }
                return value;
            case "number":
                var number = (value is Int)
                    || (value is Float) ? (value : Float) : Std.parseFloat(Std.string(value));
                if (!Math.isFinite(number)
                    || Math.abs(number) > 1000000000000.0
                    || (!(value is Int) && !(value is Float)
                        && !~/^-?(?:[0-9]+(?:\.[0-9]+)?|\.[0-9]+)$/.match(Std.string(value)))) {
                    throw new Exception('Enter a valid number for ${field.label}.');
                }
                return number;
            default:
                if (!(value is String)) {
                    throw new Exception('Enter text for ${field.label}.');
                }
                var maximum = field.kind == "textarea" ? 4000 : field.kind == "image" ? 300 : 240;
                var text = StringTools.trim(value);
                if (text.length > maximum) {
                    throw new Exception('The value for ${field.label} is too long.');
                }
                if (field.kind == "date") {
                    var valid = ~/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/.match(text);
                    try {
                        valid = valid
                            && DateTools.format(Date.fromString('${text} 12:00:00'),
                                "%Y-%m-%d") == text;
                    } catch (_:Dynamic) {
                        valid = false;
                    }
                    if (!valid) {
                        throw new Exception('Enter a valid date for ${field.label}.');
                    }
                }
                if (field.kind == "select") {
                    var allowed = false;
                    for (option in field.options) {
                        if (option.value == text) {
                            allowed = true;
                            break;
                        }
                    }
                    if (!allowed) {
                        throw new Exception('Choose an existing option for ${field.label}.');
                    }
                }
                if (field.kind == "image" && text != "" && !MediaReferences.storedImage(text)) {
                    throw new Exception('Choose an uploaded image for ${field.label}.');
                }
                return text == "" ? null : text;
        }
    }

    public static function validate(type:ContentTypeDefinition, input:Dynamic,
            requireFields:Bool):Dynamic {
        var source = decode(input);
        var result:Dynamic = {};
        var known:Map<String, Bool> = [];
        for (field in type.fields) {
            known.set(field.key, true);
            var value = validateValue(field, Reflect.field(source, field.key));
            if (requireFields && field.required && value == null) {
                throw new Exception('Complete the required field: ${field.label}.');
            }
            Reflect.setField(result, field.key, value);
        }
        for (key in Reflect.fields(source)) {
            if (!known.exists(key)) {
                throw new Exception('This collection does not define the field: ${key}.');
            }
        }
        return result;
    }

    /** Called inside the document save transaction, together with history and relations. */
    public static function save(id:Int, type:ContentTypeDefinition, values:Dynamic):Void {
        MediaLocks.run(() -> {
            for (field in type.fields) {
                var value:Dynamic = Reflect.field(values, field.key);
                if (field.kind == "image" && value != null && !MediaReferences.storedImage(value)) {
                    throw new Exception("A selected image is no longer available.");
                }
                if (value == null) {
                    ContentValue.query.where("content_id", id)
                        .where("field_key", field.key)
                        .delete();
                    continue;
                }
                ContentValue.query.upsert([
                    "content_id" => id,
                    "field_key" => field.key,
                    "value" => Json.stringify(value),
                    "value_text" => Std.string(value).substr(0, 240),
                    "value_number" => field.kind == "number" ? (value : Float) : 0.0
                ], ["content_id", "field_key"], ["value", "value_text", "value_number"]);
            }
            return true;
        });
    }

    public static function filters(type:ContentTypeDefinition,
            request:Request):Array<ContentFieldFilter> {
        var result:Array<ContentFieldFilter> = [];
        for (field in type.fields) {
            if (!field.filterable || !field.publicVisible) {
                continue;
            }
            var input = request.query('field_${field.key}', "");
            if (input == "") {
                continue;
            }
            var raw:Dynamic = field.kind == "boolean" ? input == "true" : input;
            if (field.kind == "boolean" && input != "true" && input != "false") {
                throw new Exception("Choose a valid boolean filter.");
            }
            var value = validateValue(field, raw);
            result.push({key: field.key, value: value, number: field.kind == "number"});
        }
        return result;
    }

    public static function apply(query:QueryBuilder<ContentItem>,
            filters:Array<ContentFieldFilter>):Void {
        for (filter in filters) {
            var matches = ContentValue.query.select(["content_id"]).where("field_key", filter.key);
            matches.where(filter.number ? "value_number" : "value_text",
                filter.number ? filter.value : Std.string(filter.value));
            query.whereInQuery("content_items.id", matches);
        }
    }
}
