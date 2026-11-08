package hx.press.model;

import hx.press.content.ContentColumns.ContentColumn;
import hx.well.database.query.QueryBuilder;
import hx.well.model.BaseModel;

/**
    A row of a plugin table that a content list column reads. The table is
    the column's own; `ContentColumns` checked that it belongs to the plugin.
**/
@:connection("default")
@:table("content_values")
class ContentColumnRow extends BaseModel<ContentColumnRow> {
    /** Only a column's own values are read; the key is never used. **/
    @:primary @:field public var id:Int = 0;

    /** A query of `column`'s table, limited to the rows its conditions select. **/
    public static function rows(column:ContentColumn):QueryBuilder<ContentColumnRow> {
        var row = new ContentColumnRow();
        row.setTable(column.table);
        var query = new QueryBuilder<ContentColumnRow>(row);
        for (filter in column.filters) {
            query.where('${column.table}.${filter.column}', filter.value);
        }
        return query;
    }
}
