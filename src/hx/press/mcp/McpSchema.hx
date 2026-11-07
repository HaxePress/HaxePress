package hx.press.mcp;

import haxe.Exception;
#if php
import haxe.iterators.StringIteratorUnicode;
#end

/** A field of an object schema: its name, its schema and whether it must be present. **/
typedef McpField = {
    var name:String;
    var schema:Dynamic;
    var required:Bool;
}

class McpSchemaError extends Exception {
    public final issues:Array<String>;

    public function new(issues:Array<String>) {
        super(issues.join(", "));
        this.issues = issues;
    }
}

/**
    JSON Schema (draft 2020-12) for MCP tool and prompt inputs, written as
    the official SDK publishes them, and the validator that applies them to
    arguments. Validation keeps the declared properties of an object and
    drops the others, fills in defaults, and reports every issue with its
    path, as the SDK does.
**/
class McpSchema {
    public static inline var DIALECT = "https://json-schema.org/draft/2020-12/schema";
    public static inline var MAX_INT = 2147483647;

    public static function field(name:String, schema:Dynamic):McpField {
        return {name: name, schema: schema, required: true};
    }

    public static function optional(name:String, schema:Dynamic):McpField {
        return {name: name, schema: schema, required: false};
    }

    public static function object(fields:Array<McpField>):Dynamic {
        var properties:Dynamic = {};
        var required:Array<String> = [];
        for (entry in fields) {
            Reflect.setField(properties, entry.name, entry.schema);
            if (entry.required) {
                required.push(entry.name);
            }
        }
        var schema:Dynamic = {type: "object", properties: properties};
        if (required.length > 0) {
            schema.required = required;
        }
        return schema;
    }

    /** The root schema of a tool's input, with the dialect the SDK declares. **/
    public static function input(fields:Array<McpField>):Dynamic {
        var schema = object(fields);
        Reflect.setField(schema, "$schema", DIALECT);
        return schema;
    }

    /** Adds fields to a copy of an object schema, as Zod's `extend` does. **/
    public static function extend(schema:Dynamic, fields:Array<McpField>):Dynamic {
        var properties:Dynamic = Reflect.copy(schema.properties);
        var required:Array<String> = schema.required == null ? [] : (schema.required : Array<String>)
            .copy();
        for (entry in fields) {
            Reflect.setField(properties, entry.name, entry.schema);
            required.remove(entry.name);
            if (entry.required) {
                required.push(entry.name);
            }
        }
        var result:Dynamic = Reflect.copy(schema);
        result.properties = properties;
        if (required.length > 0) {
            result.required = required;
        } else {
            Reflect.deleteField(result, "required");
        }
        return result;
    }

    /** An object schema whose properties are all optional, as Zod's `partial` does. **/
    public static function partial(schema:Dynamic):Dynamic {
        var result:Dynamic = Reflect.copy(schema);
        Reflect.deleteField(result, "required");
        return result;
    }

    /** An object schema in which the named properties must be present. **/
    public static function requiring(schema:Dynamic, names:Array<String>):Dynamic {
        var result:Dynamic = Reflect.copy(schema);
        var required:Array<String> = schema.required == null ? [] : (schema.required : Array<String>)
            .copy();
        for (name in names) {
            if (!required.contains(name)) {
                required.push(name);
            }
        }
        result.required = required;
        return result;
    }

    public static function string(?maxLength:Int, ?minLength:Int, ?pattern:String):Dynamic {
        var schema:Dynamic = {type: "string"};
        if (minLength != null) {
            schema.minLength = minLength;
        }
        if (maxLength != null) {
            schema.maxLength = maxLength;
        }
        if (pattern != null) {
            schema.pattern = pattern;
        }
        return schema;
    }

    public static function choice(values:Array<String>):Dynamic {
        return {type: "string", "enum": values};
    }

    public static function integer(minimum:Int = 1, maximum:Int = MAX_INT):Dynamic {
        return {type: "integer", minimum: minimum, maximum: maximum};
    }

    /** A whole number above zero, as Zod's `int().positive()` publishes it. **/
    public static function positive(maximum:Int = MAX_INT):Dynamic {
        return {type: "integer", exclusiveMinimum: 0, maximum: maximum};
    }

    public static function number(?minimum:Float):Dynamic {
        var schema:Dynamic = {type: "number"};
        if (minimum != null) {
            schema.minimum = minimum;
        }
        return schema;
    }

    public static function boolean():Dynamic {
        return {type: "boolean"};
    }

    public static function array(items:Dynamic, ?minItems:Int, ?maxItems:Int):Dynamic {
        var schema:Dynamic = {type: "array", items: items};
        if (minItems != null) {
            schema.minItems = minItems;
        }
        if (maxItems != null) {
            schema.maxItems = maxItems;
        }
        return schema;
    }

    /** An object with string keys and values of any type. **/
    public static function record():Dynamic {
        return {type: "object", propertyNames: {type: "string"}, additionalProperties: {}};
    }

    public static function describe(schema:Dynamic, description:String):Dynamic {
        var result:Dynamic = Reflect.copy(schema);
        result.description = description;
        return result;
    }

    public static function withDefault(schema:Dynamic, value:Dynamic):Dynamic {
        var result:Dynamic = Reflect.copy(schema);
        Reflect.setField(result, "default", value);
        return result;
    }

    /**
        Validates `value` against `schema` and returns it with undeclared
        properties removed and defaults applied. Throws `McpSchemaError`
        listing every issue.
    **/
    public static function apply(schema:Dynamic, value:Dynamic):Dynamic {
        var issues:Array<String> = [];
        var result = check(schema, value, [], issues);
        if (issues.length > 0) {
            throw new McpSchemaError(issues);
        }
        return result;
    }

    static function check(schema:Dynamic, value:Dynamic, path:Array<String>,
            issues:Array<String>):Dynamic {
        if (schema == null || Reflect.fields(schema).length == 0) {
            return value;
        }
        var expected:Null<String> = schema.type;
        var choices:Null<Array<Dynamic>> = Reflect.field(schema, "enum");
        if (value == null) {
            issue(issues, path,
                'Invalid input: expected ${expected ?? "value"}, received undefined');
            return null;
        }
        if (choices != null) {
            if (!choices.contains(value)) {
                var options = [for (entry in choices) '"${entry}"'].join("|");
                issue(issues, path, 'Invalid option: expected one of ${options}');
            }
            return value;
        }
        switch (expected) {
            case "string":
                return checkString(schema, value, path, issues);
            case "integer" | "number":
                return checkNumber(schema, value, path, issues, expected == "integer");
            case "boolean":
                if (!Std.isOfType(value, Bool)) {
                    issue(issues, path, 'Invalid input: expected boolean, received ${kind(value)}');
                }
                return value;
            case "array":
                return checkArray(schema, value, path, issues);
            case "object":
                return checkObject(schema, value, path, issues);
            default:
                return value;
        }
    }

    static function checkString(schema:Dynamic, value:Dynamic, path:Array<String>,
            issues:Array<String>):Dynamic {
        if (!Std.isOfType(value, String)) {
            issue(issues, path, 'Invalid input: expected string, received ${kind(value)}');
            return value;
        }
        var text:String = value;
        var length = characters(text);
        var minLength:Null<Int> = schema.minLength;
        var maxLength:Null<Int> = schema.maxLength;
        var pattern:Null<String> = schema.pattern;
        if (minLength != null && length < minLength) {
            issue(issues, path, 'Too small: expected string to have >=${minLength} characters');
        }
        if (maxLength != null && length > maxLength) {
            issue(issues, path, 'Too big: expected string to have <=${maxLength} characters');
        }
        if (pattern != null && !new EReg(pattern, "u").match(text)) {
            issue(issues, path, 'Invalid string: must match pattern /${pattern}/');
        }
        return text;
    }

    /** The length of a string in UTF-16 code units, as JavaScript counts it. **/
    static function characters(text:String):Int {
        #if php
        var units = 0;
        for (code in new StringIteratorUnicode(text)) {
            units += code > 0xFFFF ? 2 : 1;
        }
        return units;
        #else
        return text.length;
        #end
    }

    static function checkNumber(schema:Dynamic, value:Dynamic, path:Array<String>,
            issues:Array<String>, integer:Bool):Dynamic {
        var numeric = !Std.isOfType(value, Bool)
            && (Std.isOfType(value, Int) || Std.isOfType(value, Float));
        if (!numeric || !Math.isFinite(value)) {
            issue(issues, path, 'Invalid input: expected number, received ${kind(value)}');
            return value;
        }
        var amount:Float = value;
        if (integer && Math.ffloor(amount) != amount) {
            issue(issues, path, "Invalid input: expected int, received number");
            return value;
        }
        var minimum:Null<Float> = schema.minimum;
        var exclusiveMinimum:Null<Float> = schema.exclusiveMinimum;
        var maximum:Null<Float> = schema.maximum;
        if (minimum != null && amount < minimum) {
            issue(issues, path, 'Too small: expected number to be >=${limit(minimum)}');
        }
        if (exclusiveMinimum != null && amount <= exclusiveMinimum) {
            issue(issues, path, 'Too small: expected number to be >${limit(exclusiveMinimum)}');
        }
        if (maximum != null && amount > maximum) {
            issue(issues, path, 'Too big: expected number to be <=${limit(maximum)}');
        }
        if (integer && Std.isOfType(value, Float) && Math.abs(amount) <= MAX_INT) {
            return Std.int(amount);
        }
        return value;
    }

    static function checkArray(schema:Dynamic, value:Dynamic, path:Array<String>,
            issues:Array<String>):Dynamic {
        if (!Std.isOfType(value, Array)) {
            issue(issues, path, 'Invalid input: expected array, received ${kind(value)}');
            return value;
        }
        var items:Array<Dynamic> = value;
        var minItems:Null<Int> = schema.minItems;
        var maxItems:Null<Int> = schema.maxItems;
        if (minItems != null && items.length < minItems) {
            issue(issues, path, 'Too small: expected array to have >=${minItems} items');
        }
        if (maxItems != null && items.length > maxItems) {
            issue(issues, path, 'Too big: expected array to have <=${maxItems} items');
        }
        var result:Array<Dynamic> = [];
        for (index in 0...items.length) {
            result.push(check(schema.items, items[index], path.concat(['${index}']), issues));
        }
        return result;
    }

    static function checkObject(schema:Dynamic, value:Dynamic, path:Array<String>,
            issues:Array<String>):Dynamic {
        if (!isObject(value)) {
            issue(issues, path, 'Invalid input: expected object, received ${kind(value)}');
            return value;
        }
        var properties:Dynamic = schema.properties;
        var open = Reflect.hasField(schema, "additionalProperties");
        var result:Dynamic = {};
        if (open) {
            for (name in Reflect.fields(value)) {
                Reflect.setField(result, name, Reflect.field(value, name));
            }
        }
        if (properties == null) {
            return result;
        }
        var required:Array<String> = schema.required == null ? [] : schema.required;
        for (name in Reflect.fields(properties)) {
            var definition:Dynamic = Reflect.field(properties, name);
            var present = Reflect.hasField(value, name) && Reflect.field(value, name) != null;
            if (!present) {
                if (Reflect.hasField(definition, "default")) {
                    Reflect.setField(result, name, Reflect.field(definition, "default"));
                } else if (required.contains(name)) {
                    check(definition, null, path.concat([name]), issues);
                }
                continue;
            }
            Reflect.setField(result, name,
                check(definition, Reflect.field(value, name), path.concat([name]), issues));
        }
        return result;
    }

    /** A schema bound as text: whole numbers without a fraction. **/
    static function limit(value:Float):String {
        return Math.ffloor(value) == value
            && Math.abs(value) < 1e15 ? '${Std.int(value)}' : '${value}';
    }

    public static function isObject(value:Dynamic):Bool {
        return value != null && Type.typeof(value) == TObject;
    }

    static function kind(value:Dynamic):String {
        if (Std.isOfType(value, String)) {
            return "string";
        }
        if (Std.isOfType(value, Bool)) {
            return "boolean";
        }
        if (Std.isOfType(value, Int) || Std.isOfType(value, Float)) {
            return "number";
        }
        if (Std.isOfType(value, Array)) {
            return "array";
        }
        return "object";
    }

    static function issue(issues:Array<String>, path:Array<String>, message:String):Void {
        issues.push(path.length == 0 ? message : '${path.join(".")}: ${message}');
    }
}
