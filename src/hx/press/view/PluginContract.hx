package hx.press.view;

import haxe.Exception;
import haxe.Json;
import wellout.check.HostContract;
import wellout.check.Types;
import wellout.syntax.Diagnostic;
import wellout.syntax.ExpressionParser;

/**
    The `contract.json` of a plugin's views: the view types its pages read
    and the islands they mount, added to a copy of the application's
    contract. Types use the template type syntax, such as
    `List<ReportRow>` or `String?`; types may refer to each other.
**/
class PluginContract {
    public static inline final FILENAME = "contract.json";
    static inline final MAX_TYPES = 64;
    static inline final MAX_FIELDS = 64;
    static inline final MAX_ISLANDS = 16;
    static inline final MAX_MESSAGES = 200;

    public static function parse(text:String):Dynamic {
        var parsed:Dynamic = Json.parse(text);
        if (!isObject(parsed)) {
            throw new Exception("The views contract must be a JSON object.");
        }
        return parsed;
    }

    /** Adds the declared view types and islands; returns the island module URLs. **/
    public static function declare(contract:HostContract, definition:Dynamic,
            assetBase:String):Map<String, String> {
        var views = entries(definition.views, MAX_TYPES, "view types");
        var records:Array<{record:RecordType, fields:Dynamic}> = [];
        for (name => fields in views) {
            if (!~/^[A-Z][A-Za-z0-9]{0,79}$/.match(name) || contract.viewType(name) != null) {
                throw new Exception('The view type ${name} is not allowed.');
            }
            var record = new RecordType(name, []);
            contract.addView(record);
            records.push({record: record, fields: fields});
        }
        // Every type is declared before fields are resolved, so types may refer to each other.
        for (entry in records) {
            for (field in fieldList(contract, entry.fields, entry.record.name)) {
                entry.record.fields.push(field);
            }
        }
        var modules:Map<String, String> = [];
        for (name => island in entries(definition.islands, MAX_ISLANDS, "islands")) {
            if (!~/^[a-z][a-z0-9-]{0,63}$/.match(name) || contract.island(name) != null) {
                throw new Exception('The island ${name} is not allowed.');
            }
            if (!isObject(island)) {
                throw new Exception('The island ${name} must be described by an object.');
            }
            var module:Dynamic = island.module;
            if (!Std.isOfType(module, String) || !assetPath(module)) {
                throw new Exception('The island ${name} must load a JavaScript file in public/.');
            }
            var props = island.props == null ? {} : island.props;
            var fields = fieldList(contract, props, name);
            contract.addIsland(new IslandSignature(name, TRecord(fields),
                messageList(island.messages, name)));
            modules.set(name, '${assetBase}${module}');
        }
        return modules;
    }

    static function fieldList(contract:HostContract, fields:Dynamic,
            owner:String):Array<FieldInfo> {
        var result:Array<FieldInfo> = [];
        for (name => declared in entries(fields, MAX_FIELDS, 'fields of ${owner}')) {
            if (!~/^[a-z][A-Za-z0-9_]{0,63}$/.match(name)) {
                throw new Exception('The field ${owner}.${name} is not allowed.');
            }
            if (!Std.isOfType(declared, String)) {
                throw new Exception('The field ${owner}.${name} must name a type.');
            }
            result.push(new FieldInfo(name, resolve(contract, declared, '${owner}.${name}')));
        }
        return result;
    }

    static function resolve(contract:HostContract, text:String, owner:String):WellType {
        var parsed = ExpressionParser.parseType(text);
        var diagnostics:Array<Diagnostic> = parsed.diagnostics.copy();
        var type = parsed.value == null ? null : Types.resolve(parsed.value, contract, diagnostics);
        if (type == null || diagnostics.filter(item -> item.isError()).length > 0) {
            var problem = diagnostics.length == 0 ? "invalid type" : diagnostics[0].message;
            throw new Exception('The type of ${owner} is not valid: ${problem}');
        }
        return type;
    }

    static function messageList(input:Dynamic, owner:String):Array<String> {
        if (input == null) {
            return [];
        }
        if (!Std.isOfType(input, Array)) {
            throw new Exception('The messages of ${owner} must be a list.');
        }
        var keys:Array<Dynamic> = input;
        if (keys.length > MAX_MESSAGES) {
            throw new Exception('The island ${owner} declares too many messages.');
        }
        var result:Array<String> = [];
        for (key in keys) {
            if (!Std.isOfType(key, String) || key == "" || (key : String).length > 500) {
                throw new Exception('The messages of ${owner} must be text.');
            }
            result.push(key);
        }
        return result;
    }

    /** The fields of a JSON object in their written order. **/
    static function entries(input:Dynamic, maximum:Int, label:String):Map<String, Dynamic> {
        var result:Map<String, Dynamic> = [];
        if (input == null) {
            return result;
        }
        if (!isObject(input)) {
            throw new Exception('The ${label} must be a JSON object.');
        }
        var names = Reflect.fields(input);
        if (names.length > maximum) {
            throw new Exception('The views contract declares too many ${label}.');
        }
        for (name in names) {
            result.set(name, Reflect.field(input, name));
        }
        return result;
    }

    /** A JavaScript file in the package's `public/` folder, without `..` or hidden segments. **/
    static function assetPath(path:String):Bool {
        if (path.length > 240
            || !~/^[A-Za-z0-9_\/-]+(\.[A-Za-z0-9_-]+)*\.(mjs|js)(?![\s\S])/.match(path)) {
            return false;
        }
        for (segment in path.split("/")) {
            if (segment == "" || StringTools.startsWith(segment, ".")) {
                return false;
            }
        }
        return true;
    }

    static function isObject(value:Dynamic):Bool {
        return value != null
            && Reflect.isObject(value)
            && !Std.isOfType(value, Array)
            && !Std.isOfType(value, String);
    }
}
