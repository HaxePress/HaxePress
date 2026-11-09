package hx.press.content;

import hx.press.i18n.Languages;
import haxe.Int64;
import haxe.Json;
import hx.press.CmsAccess;
import hx.press.Pagination.PageCursor;
import hx.press.content.ContentColumns.ContentColumn;
import hx.press.content.ContentTypeDefinition.ContentFieldDefinition;
import hx.press.i18n.I18n;
import hx.press.model.AdminPreference;
import hx.press.model.ContentColumnRow;
import hx.press.model.ContentItem;
import hx.press.model.ContentValue;
import hx.press.view.ContentAdminRows;
import hx.well.database.query.QueryBuilder;

/** Where a list column's values come from. **/
enum ContentListSource {
    /** A column of `content_items`. **/
    Own(column:String);

    /** A custom field, from `content_values`. **/
    Field(field:ContentFieldDefinition);

    /** A plugin's column, from its own table. **/
    Plugin(column:ContentColumn);
}

typedef ContentListColumn = {
    /** `title`, `status`, `category`, `updated`, `field.<key>` or `<plugin>.<key>`. **/
    var key:String;

    var label:String;

    /** How a cell shows: `title`, `status`, `updated` or `value`. **/
    var cell:String;

    /** Numbers and dates sort descending first, text ascending. **/
    var numeric:Bool;

    var source:ContentListSource;
}

typedef ContentListLayout = {
    /** Every column the list can show, in the administrator's order. **/
    var columns:Array<ContentListColumn>;

    var hidden:Array<String>;
    var visible:Array<ContentListColumn>;
}

typedef ContentListSort = {
    var column:ContentListColumn;
    var descending:Bool;

    /** Whether the administrator chose it; the list is otherwise newest first. **/
    var chosen:Bool;
}

typedef ContentListCell = {
    var kind:String;
    var text:String;
    var translate:Bool;
}

private typedef SavedLayout = {
    var order:Array<String>;
    var hidden:Array<String>;
}

/**
    The columns of an admin content list. Each collection lists its own
    columns, its custom fields shown in lists and the columns of active
    plugins. Every administrator orders, hides and sorts them for
    themselves; a column they have not placed yet is visible beside the
    column it follows by default. Sorting happens in SQL with a cursor on
    the sorted value and the item ID.
**/
class ContentListColumns {
    static inline var SORT_ALIAS = "__cms_sort";
    static inline var MAX_KEYS = 64;

    /** The longest sort value a page cursor carries: `content_values.value_text`. **/
    public static inline var MAX_SORT_VALUE = 240;

    /** Every column of collection `type`, in the default order. **/
    public static function available(type:ContentTypeDefinition):Array<ContentListColumn> {
        var columns:Array<ContentListColumn> = [];
        var titleLabel = type.singular != "" ? I18n.t(type.singular) : I18n.t("Content item");
        columns.push(own("title", titleLabel, "title", false, "title"));
        columns.push(own("status", I18n.t("Status"), "status", false, "status"));
        if (ContentTypes.supports(type, "categories")) {
            columns.push(own("category", I18n.t("Category"), "value", false, "category"));
        }
        if (Languages.prefixed()) {
            columns.push(own("language", I18n.t("Language"), "value", false, "language"));
        }
        for (field in ContentAdminRows.listFields(type)) {
            columns.push({
                key: 'field.${field.key}',
                label: field.label,
                cell: "value",
                numeric: field.kind == "number",
                source: Field(field)
            });
        }
        for (column in ContentColumns.forCollection(type.key)) {
            if (column.capability != "" && !CmsAccess.can(column.capability)) {
                continue;
            }
            columns.push({
                key: column.key,
                label: I18n.t(column.label, null, column.namespace),
                cell: "value",
                numeric: column.kind == "number",
                source: Plugin(column)
            });
        }
        columns.push(own("updated", I18n.t("Last updated"), "updated", true, "updated_at"));
        return columns;
    }

    /** The columns `adminId` sees in collection `type`'s list. **/
    public static function layout(adminId:Int, type:ContentTypeDefinition):ContentListLayout {
        return arrange(available(type), saved(adminId, type.key));
    }

    /**
        Stores `adminId`'s columns for collection `type`: the visible keys in
        `order`, after moving `move` (`<key>:up` or `<key>:down`) one place.
        Columns of plugins that are not active keep their place and choice.
        At least one column stays visible.
    **/
    public static function save(adminId:Int, type:ContentTypeDefinition, order:Array<String>,
            visible:Array<String>, move:String):Void {
        var columns = available(type);
        var keys = [for (column in columns) column.key];
        var previous = saved(adminId, type.key);
        var current = arrange(columns, previous).columns.map(column -> column.key);
        var requested = [for (key in order) if (keys.contains(key)) key];
        var arranged = requested.length == current.length
            && Lambda.foreach(current, key -> requested.contains(key)) ? requested : current;
        moved(arranged, move);
        var shown = [for (key in visible) if (keys.contains(key)) key];
        if (shown.length == 0) {
            shown = [arranged[0]];
        }
        var hidden = [for (key in arranged) if (!shown.contains(key)) key];
        // Columns that are not available now keep their place and choice for later.
        var stored = arranged.copy();
        var previousOrder = previous == null ? [] : previous.order;
        for (index in 0...previousOrder.length) {
            var key = previousOrder[index];
            if (keys.contains(key) || stored.contains(key)) {
                continue;
            }
            var after = index == 0 ? -1 : stored.indexOf(previousOrder[index - 1]);
            stored.insert(after + 1, key);
        }
        if (previous != null) {
            for (key in previous.hidden) {
                if (!keys.contains(key) && !hidden.contains(key)) {
                    hidden.push(key);
                }
            }
        }
        var value = Json.stringify({
            order: stored.slice(0, MAX_KEYS),
            hidden: hidden.slice(0, MAX_KEYS)
        });
        AdminPreference.query.upsert([
            "admin_id" => adminId,
            "preference" => preference(type.key),
            "value" => value,
            "updated_epoch" => Date.now().getTime()
        ], ["admin_id", "preference"], ["value", "updated_epoch"]);
    }

    /** Returns `adminId`'s columns for collection `type` to the default ones. **/
    public static function reset(adminId:Int, type:ContentTypeDefinition):Void {
        AdminPreference.query.where("admin_id", adminId)
            .where("preference", preference(type.key))
            .delete();
    }

    /**
        The order the list is in: the visible column `key` in `direction`
        (`asc` or `desc`), or the most recently updated first.
    **/
    public static function sort(layout:ContentListLayout, key:String,
            direction:String):ContentListSort {
        for (column in layout.visible) {
            if (column.key == key) {
                var descending = direction == "" ? column.numeric : direction == "desc";
                return {column: column, descending: descending, chosen: true};
            }
        }
        var updated = Lambda.find(layout.columns, column -> column.key == "updated");
        return {column: updated, descending: true, chosen: false};
    }

    /** The direction a heading link sorts by: the other way when the list is sorted by it already. **/
    public static function nextDirection(sort:ContentListSort, column:ContentListColumn):String {
        if (sort.column.key == column.key) {
            return sort.descending ? "asc" : "desc";
        }
        return column.numeric ? "desc" : "asc";
    }

    /**
        Selects what the visible plugin columns show and the sorted value,
        orders the rows and continues after `cursor`.
    **/
    public static function apply(query:QueryBuilder<ContentItem>,
            visible:Array<ContentListColumn>, sort:ContentListSort, cursor:Null<PageCursor>):Void {
        for (column in visible) {
            switch (column.source) {
                case Plugin(plugin):
                    query.selectSub(pluginValue(plugin), alias(column.key));
                case _:
            }
        }
        var sorted = sortReference(query, sort.column);
        var descending = cursor != null && cursor.before ? !sort.descending : sort.descending;
        if (cursor != null) {
            continueAfter(query, sort.column, sorted, cursor, descending);
        }
        var direction = descending ? "DESC" : "ASC";
        query.orderBy(sorted, direction).orderBy("id", direction);
    }

    /** Whether the page depends on plugin tables, which the content cache does not follow. **/
    public static function readsPlugins(visible:Array<ContentListColumn>,
            sort:ContentListSort):Bool {
        for (column in visible.concat([sort.column])) {
            switch (column.source) {
                case Plugin(_):
                    return true;
                case _:
            }
        }
        return false;
    }

    /** A row's sorted value, for its page cursor. **/
    public static function sortValue(record:Dynamic, sort:ContentListSort):Null<String> {
        var value:Dynamic = switch (sort.column.source) {
            case Own(column): Reflect.field(record, column);
            case _: Reflect.field(record, SORT_ALIAS);
        };
        if (value == null) {
            return null;
        }
        var text = Std.string(value);
        return text.length > MAX_SORT_VALUE ? text.substr(0, MAX_SORT_VALUE) : text;
    }

    /** The cells of a row for the visible columns. `summary` holds the row's presentation. **/
    public static function cells(record:Dynamic, summary:Dynamic,
            visible:Array<ContentListColumn>):Array<ContentListCell> {
        var cells:Array<ContentListCell> = [];
        for (column in visible) {
            switch (column.source) {
                case Own("category"):
                    var category:String = summary.category ?? "";
                    cells.push({
                        kind: "value",
                        text: category == "" ? "—" : category,
                        translate: false
                    });
                case Own("language"):
                    var language:String = summary.language ?? "";
                    cells.push({kind: "value", text: Languages.name(language), translate: false});
                case Own(_):
                    cells.push({kind: column.cell, text: "", translate: false});
                case Field(field):
                    var values:Dynamic = summary.fields;
                    var shown = ContentAdminRows.column(field,
                        values == null ? null : Reflect.field(values, field.key));
                    cells.push({kind: "value", text: shown.text, translate: shown.translate});
                case Plugin(plugin):
                    var value:Dynamic = Reflect.field(record, alias(column.key));
                    cells.push({kind: "value", text: pluginText(plugin, value), translate: false});
            }
        }
        return cells;
    }

    /** The cursor value that a page cursor for `sort` carries, or the cursor unchanged. **/
    public static function validCursor(cursor:Null<PageCursor>,
            sort:ContentListSort):Null<PageCursor> {
        if (cursor == null || cursor.value == null || !sort.column.numeric) {
            return cursor;
        }
        switch (sort.column.source) {
            case Own(_):
                return cursor;
            case _:
                return Math.isNaN(Std.parseFloat(cursor.value)) ? null : cursor;
        }
    }

    static function own(key:String, label:String, cell:String, numeric:Bool,
            column:String):ContentListColumn {
        return {
            key: key,
            label: label,
            cell: cell,
            numeric: numeric,
            source: Own(column)
        };
    }

    static function preference(kind:String):String {
        return 'content-columns:${kind}';
    }

    static function saved(adminId:Int, kind:String):Null<SavedLayout> {
        var row = AdminPreference.query.select(["value"])
            .where("admin_id", adminId)
            .where("preference", preference(kind))
            .limit(1)
            .first();
        if (row == null) {
            return null;
        }
        try {
            var parsed:Dynamic = Json.parse(row.value);
            return {order: keys(parsed.order), hidden: keys(parsed.hidden)};
        } catch (_:Dynamic) {
            return null;
        }
    }

    static function keys(value:Dynamic):Array<String> {
        if (!Std.isOfType(value, Array)) {
            return [];
        }
        var list:Array<Dynamic> = value;
        return [
            for (item in list.slice(0, MAX_KEYS))
                if (Std.isOfType(item, String)) (item : String)
        ];
    }

    /** Puts `columns` in `saved` order; a column not placed yet follows its default predecessor. **/
    static function arrange(columns:Array<ContentListColumn>,
            saved:Null<SavedLayout>):ContentListLayout {
        if (saved == null) {
            return {columns: columns, hidden: [], visible: columns};
        }
        var byKey = [for (column in columns) column.key => column];
        var ordered:Array<ContentListColumn> = [];
        for (key in saved.order) {
            var column = byKey.get(key);
            if (column != null && !ordered.contains(column)) {
                ordered.push(column);
            }
        }
        for (index in 0...columns.length) {
            var column = columns[index];
            if (ordered.contains(column)) {
                continue;
            }
            var position = 0;
            var before = index - 1;
            while (before >= 0) {
                var found = ordered.indexOf(columns[before]);
                if (found >= 0) {
                    position = found + 1;
                    break;
                }
                before--;
            }
            ordered.insert(position, column);
        }
        var hidden = [for (key in saved.hidden) if (byKey.exists(key)) key];
        var visible = [for (column in ordered) if (!hidden.contains(column.key)) column];
        if (visible.length == 0) {
            visible = [ordered[0]];
            hidden.remove(ordered[0].key);
        }
        return {columns: ordered, hidden: hidden, visible: visible};
    }

    static function moved(order:Array<String>, move:String):Void {
        var separator = move.lastIndexOf(":");
        if (separator < 0) {
            return;
        }
        var key = move.substr(0, separator);
        var direction = move.substr(separator + 1);
        var index = order.indexOf(key);
        var target = direction == "up" ? index - 1 : direction == "down" ? index + 1 : -1;
        if (index < 0 || target < 0 || target >= order.length) {
            return;
        }
        order[index] = order[target];
        order[target] = key;
    }

    static function alias(key:String):String {
        var name = new StringBuf();
        name.add("__cms_column_");
        for (index in 0...key.length) {
            var code = StringTools.fastCodeAt(key, index);
            var plain = (code >= "a".code && code <= "z".code)
                || (code >= "0".code && code <= "9".code);
            name.addChar(plain ? code : "_".code);
        }
        return name.toString();
    }

    static function pluginValue(column:ContentColumn):QueryBuilder<ContentColumnRow> {
        return ContentColumnRow.rows(column)
            .select(['${column.table}.${column.value}'])
            .whereColumn('${column.table}.${column.content}', "content_items.id")
            .limit(1);
    }

    /** Selects the sorted value when it is not a column of `content_items` and returns its name. **/
    static function sortReference(query:QueryBuilder<ContentItem>,
            column:ContentListColumn):String {
        switch (column.source) {
            case Own(name):
                return name;
            case Field(field):
                var value = ContentValue.query.select([fieldValue(field)])
                    .whereColumn("content_values.content_id", "content_items.id")
                    .where("field_key", field.key)
                    .limit(1);
                query.selectSub(value, SORT_ALIAS);
            case Plugin(plugin):
                query.selectSub(pluginValue(plugin), SORT_ALIAS);
        }
        return SORT_ALIAS;
    }

    static function fieldValue(field:ContentFieldDefinition):String {
        return field.kind == "number" ? "value_number" : "value_text";
    }

    /**
        Rows after `cursor` in the given direction. An item without a value
        sorts lowest, as SQLite and MySQL order nulls, so it comes last when
        descending and first when ascending.
    **/
    static function continueAfter(query:QueryBuilder<ContentItem>, column:ContentListColumn,
            sorted:String, cursor:PageCursor, descending:Bool):Void {
        var comparison = descending ? "<" : ">";
        var value:Dynamic = cursor.value == null ? null : column.numeric
            && !isOwn(column) ? Std.parseFloat(cursor.value) : cursor.value;
        switch (column.source) {
            case Own(name):
                query.where(matches -> {
                    matches.where(name, comparison, value).orWhere(same -> {
                        same.where(name, value).where("id", comparison, cursor.id);
                    });
                });
            case _:
                if (value == null && descending) {
                    query.whereNotInQuery("id", valued(column)).where("id", comparison, cursor.id);
                } else if (value == null) {
                    query.where(matches -> {
                        matches.where(empty -> {
                            empty.whereNotInQuery("id", valued(column))
                                .where("id", comparison, cursor.id);
                        }).orWhere(present -> present.whereInQuery("id", valued(column)));
                    });
                } else {
                    query.where(matches -> {
                        matches.whereInQuery("id", valuedWhere(column, comparison, value))
                            .orWhere(same -> {
                                same.whereInQuery("id", valuedWhere(column, "=", value))
                                    .where("id", comparison, cursor.id);
                            });
                        if (descending) {
                            matches.orWhere(empty -> empty.whereNotInQuery("id", valued(column)));
                        }
                    });
                }
        }
    }

    static function isOwn(column:ContentListColumn):Bool {
        return switch (column.source) {
            case Own(_): true;
            case _: false;
        };
    }

    /** The IDs of the items that have a value for `column`. **/
    static function valued(column:ContentListColumn):Dynamic {
        return switch (column.source) {
            case Field(field):
                ContentValue.query.select(["content_id"]).where("field_key", field.key);
            case Plugin(plugin):
                ContentColumnRow.rows(plugin).select([plugin.content]);
            case Own(_):
                null;
        };
    }

    static function valuedWhere(column:ContentListColumn, comparison:String,
            value:Dynamic):Dynamic {
        return switch (column.source) {
            case Field(field):
                ContentValue.query.select(["content_id"])
                    .where("field_key", field.key)
                    .where(fieldValue(field), comparison, value);
            case Plugin(plugin):
                ContentColumnRow.rows(plugin)
                    .select([plugin.content])
                    .where(plugin.value, comparison, value);
            case Own(_):
                null;
        };
    }

    static function pluginText(column:ContentColumn, value:Dynamic):String {
        if (value == null) {
            return column.empty;
        }
        if (column.kind == "number" && !Std.isOfType(value, String)) {
            var number:Float = value;
            if (Math.isFinite(number) && Math.ffloor(number) == number && Math.abs(number) < 1e15) {
                return Std.string(Int64.fromFloat(number));
            }
        }
        return Std.string(value);
    }
}
