package hx.press.view;

import haxe.ds.IntMap;
import haxe.ds.StringMap;

/** Converts host values to plain JSON-ready values: maps become objects, functions are called. */
class ViewData {
    public static function plain(value:Dynamic, depth:Int = 0):Dynamic {
        if (value == null || depth > 48) {
            return null;
        }
        if (Std.isOfType(value, String)
            || Std.isOfType(value, Bool)
            || Std.isOfType(value, Int)
            || Std.isOfType(value, Float)) {
            return value;
        }
        if (Reflect.isFunction(value)) {
            return plain(value(), depth + 1);
        }
        if (Std.isOfType(value, Array)) {
            var items:Array<Dynamic> = cast value;
            return [for (item in items) plain(item, depth + 1)];
        }
        if (Std.isOfType(value, StringMap)) {
            var map:StringMap<Dynamic> = cast value;
            var object:Dynamic = {};
            for (key in map.keys()) {
                Reflect.setField(object, key, plain(map.get(key), depth + 1));
            }
            return object;
        }
        if (Std.isOfType(value, IntMap)) {
            var map:IntMap<Dynamic> = cast value;
            var object:Dynamic = {};
            for (key in map.keys()) {
                Reflect.setField(object, Std.string(key), plain(map.get(key), depth + 1));
            }
            return object;
        }
        if (Std.isOfType(value, Date)) {
            return Std.string(value);
        }
        var object:Dynamic = {};
        for (field in Reflect.fields(value)) {
            Reflect.setField(object, field, plain(Reflect.field(value, field), depth + 1));
        }
        return object;
    }

    /** Copies the fields of `source` into `target`, converting values. **/
    public static function assign(target:Dynamic, source:Dynamic):Void {
        if (source == null) {
            return;
        }
        if (Std.isOfType(source, StringMap)) {
            var map:StringMap<Dynamic> = cast source;
            for (key in map.keys()) {
                Reflect.setField(target, key, plain(map.get(key)));
            }
            return;
        }
        for (field in Reflect.fields(source)) {
            Reflect.setField(target, field, plain(Reflect.field(source, field)));
        }
    }
}
