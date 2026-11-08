package hx.press.content;

import haxe.Exception;
import haxe.ThreadLocal;
import hx.press.plugins.PluginDatabase;
#if target.threaded
import sys.thread.Mutex;
#else
import hx.well.thread.FakeMutex as Mutex;
#end

/** A column a plugin adds to the admin content lists. **/
typedef ContentColumnDefinition = {
    /** Lowercase letters, digits and underscores, unique within the plugin. **/
    var key:String;

    /** The column heading, a key in the plugin's catalogue (`namespace`). **/
    var label:String;

    /** A table of the plugin with at most one row for each content item. **/
    var table:String;

    /** The column of `table` shown and sorted; it must not hold null. **/
    var value:String;

    /** The column of `table` that holds the content item's ID; `content_id` when left out. **/
    @:optional var content:String;

    /** `number` (the default) or `text`: how cells are shown and compared. **/
    @:optional var kind:String;

    /** What an item without a row shows; `—` when left out. **/
    @:optional var empty:String;

    /** The catalogue the label is in; the plugin's own when left out. **/
    @:optional var namespace:String;

    /** The collections that show the column; every collection when left out. **/
    @:optional var collections:Array<String>;

    /** Column values the rows must have, such as `{country: "TR"}`. **/
    @:optional var where:Dynamic;

    /** The capability a member needs to see the column; anyone who sees the list when left out. **/
    @:optional var capability:String;
}

/** A column a plugin added, and the handle that removes it. **/
class ContentColumn {
    /** The plugin's package ID. **/
    public final owner:String;

    /** `<owner>.<key>`, which preferences and sort links use. **/
    public final key:String;

    public final label:String;
    public final namespace:String;
    public final table:String;
    public final content:String;
    public final value:String;
    public final kind:String;
    public final empty:String;
    public final collections:Array<String>;
    public final filters:Array<{column:String, value:Dynamic}>;
    public final capability:String;

    @:allow(hx.press.content.ContentColumns)
    function new(owner:String, definition:ContentColumnDefinition,
            filters:Array<{column:String, value:Dynamic}>) {
        this.owner = owner;
        this.key = '${owner}.${definition.key}';
        this.label = definition.label;
        this.namespace = definition.namespace ?? owner;
        this.table = definition.table;
        this.content = definition.content ?? "content_id";
        this.value = definition.value;
        this.kind = definition.kind ?? "number";
        this.empty = definition.empty ?? "—";
        this.collections = definition.collections == null ? [] : definition.collections.copy();
        this.filters = filters;
        this.capability = definition.capability ?? "";
    }

    /** Whether the lists of collection `kind` show this column. **/
    public function shows(kind:String):Bool {
        return collections.length == 0 || collections.contains(kind);
    }
}

private class CollectedColumns {
    public final owner:String;
    public final slug:String;
    public final added:Array<ContentColumn> = [];

    public function new(owner:String, slug:String) {
        this.owner = owner;
        this.slug = slug;
    }
}

/**
    Columns plugins add to the admin content lists. A plugin adds them in
    `onCreate` and removes them in `onDestroy`; when it stops, the runtime
    removes what it left. Each column reads one value per content item from
    a table of the plugin, so the list shows and sorts it in its own query.
    Administrators choose which columns they see and in which order; a new
    column is visible until they hide it.
**/
class ContentColumns {
    static final writes = new Mutex();
    static final collecting = new ThreadLocal<CollectedColumns>();
    static var added:Array<ContentColumn> = [];

    /** Adds a column while the plugin is created and returns the handle that removes it. **/
    public static function add(definition:ContentColumnDefinition):ContentColumn {
        var plugin = collecting.get();
        if (plugin == null) {
            throw new Exception("Add content columns in the plugin's onCreate.");
        }
        if (definition == null) {
            throw new Exception("Describe the content column to add.");
        }
        var column = new ContentColumn(plugin.owner, definition, filters(definition.where));
        validate(column, definition.key, plugin.slug);
        writes.acquire();
        var exists = Lambda.exists(added, item -> item.key == column.key);
        if (!exists) {
            added = added.concat([column]);
        }
        writes.release();
        if (exists) {
            throw new Exception('The content column ${column.key} already exists.');
        }
        plugin.added.push(column);
        return column;
    }

    /** Removes a column added with `add`. Removing it again does nothing. **/
    public static function remove(column:ContentColumn):Void {
        if (column == null) {
            return;
        }
        writes.acquire();
        if (added.contains(column)) {
            added = added.filter(item -> item != column);
        }
        writes.release();
    }

    /** The columns active plugins add to the lists of collection `kind`, in the order they were added. **/
    public static function forCollection(kind:String):Array<ContentColumn> {
        return [for (column in added) if (column.shows(kind)) column];
    }

    /**
        Runs a plugin's creation and returns the columns it added, so the
        runtime can remove what the plugin leaves when it stops. A failed
        creation removes its columns before the error is rethrown.
    **/
    public static function collect(owner:String, slug:String,
            callback:Void->Void):Array<ContentColumn> {
        var previous = collecting.get();
        var plugin = new CollectedColumns(owner, slug);
        collecting.set(plugin);
        try {
            callback();
        } catch (error:Dynamic) {
            collecting.set(previous);
            for (column in plugin.added) {
                remove(column);
            }
            throw error;
        }
        collecting.set(previous);
        return plugin.added;
    }

    static function filters(where:Dynamic):Array<{column:String, value:Dynamic}> {
        if (where == null) {
            return [];
        }
        if (!Reflect.isObject(where) || Std.isOfType(where, String)) {
            throw new Exception("A content column's where must be an object of column values.");
        }
        var result:Array<{column:String, value:Dynamic}> = [];
        for (column in Reflect.fields(where)) {
            var value:Dynamic = Reflect.field(where, column);
            if (!Std.isOfType(value, String) && !Std.isOfType(value, Float)) {
                throw new Exception('The content column condition ${column} must be text or a number.');
            }
            result.push({column: column, value: value});
        }
        return result;
    }

    static function validate(column:ContentColumn, key:String, slug:String):Void {
        if (!identifier(key, 40)) {
            throw new Exception("A content column key uses lowercase letters, digits and underscores.");
        }
        if (!Std.isOfType(column.label, String) || StringTools.trim(column.label) == ""
            || column.label.length > 80) {
            throw new Exception('The content column ${key} needs a label of at most 80 characters.');
        }
        if (!identifier(column.table, 64)
            || !StringTools.startsWith(column.table, PluginDatabase.prefix(slug))) {
            throw new Exception('The content column ${key} must read a table of its own plugin.');
        }
        for (name in [column.content, column.value].concat([for (filter in column.filters) filter.column])) {
            if (!identifier(name, 64)) {
                throw new Exception('The content column ${key} names an invalid table column.');
            }
        }
        if (column.kind != "number" && column.kind != "text") {
            throw new Exception('The content column ${key} must be a number or text column.');
        }
        if (!Std.isOfType(column.capability, String) || column.capability.length > 64) {
            throw new Exception('The content column ${key} names an invalid capability.');
        }
        if (!Std.isOfType(column.empty, String) || column.empty.length > 40) {
            throw new Exception('The empty text of the content column ${key} is too long.');
        }
        for (collection in column.collections) {
            if (!Std.isOfType(collection, String) || !ContentTypes.validKey(collection)) {
                throw new Exception('The content column ${key} names an invalid collection.');
            }
        }
    }

    /** Lowercase letters, digits and underscores, starting with a letter. **/
    static function identifier(text:Dynamic, maximum:Int):Bool {
        if (!Std.isOfType(text, String)) {
            return false;
        }
        var value:String = text;
        if (value.length == 0 || value.length > maximum) {
            return false;
        }
        for (index in 0...value.length) {
            var code = StringTools.fastCodeAt(value, index);
            var letter = code >= "a".code && code <= "z".code;
            var digit = code >= "0".code && code <= "9".code;
            if (!(letter || (index > 0 && (digit || code == "_".code)))) {
                return false;
            }
        }
        return true;
    }
}
