package hx.press.backup;

#if jvm
import haxe.Exception;
import haxe.Int64;
import haxe.Json;
import haxe.crypto.Base64;
import haxe.io.Bytes;
import haxe.io.BytesOutput;
import haxe.io.Eof;
import haxe.io.Input;
import hx.press.backup.BackupTable.BackupTableDefinition;
import hx.well.database.query.QueryBuilder;
import hx.well.storage.StorageDisk;
import java.math.BigDecimal;
import sys.db.ResultSet;

class BackupRows extends Input {
    static inline var BATCH = 16;

    final table:BackupTableDefinition;
    final query:Void->QueryBuilder<Dynamic>;
    final columns:Array<String>;
    final asText:Array<String>;
    final ordering:Array<String>;
    final numericKeys:Array<Bool>;
    final transform:Dynamic->Void;
    var page:Null<ResultSet>;
    var pageCount = 0;
    var cursor:Array<Dynamic> = [];
    var buffer = Bytes.alloc(0);
    var offset = 0;

    public function new(table:BackupTableDefinition, query:Void->QueryBuilder<Dynamic>,
            transform:Dynamic->Void, ?content:Bool = false) {
        this.table = table;
        this.query = query;
        this.transform = transform;
        columns = table.columns.map(column -> column.name);
        asText = BackupTable.textColumns(table);
        ordering = table.primary.map(key -> '${table.name}.${key}');
        numericKeys = table.primary.map(key -> {
            var kind = table.columns.filter(column -> column.name == key)[0].kind;
            return BackupTable.integer(kind) || kind == "decimal";
        });
        if (content) {
            asText.remove("id");
        }
    }

    public static function path(table:String):String {
        return 'database/${table}.rows';
    }

    function nextPage():ResultSet {
        var rows = query().selectWithText(columns, asText).limit(BATCH);
        for (key in ordering) {
            rows.orderBy(key);
        }
        if (cursor.length > 0) {
            rows.whereAfterKey(ordering, cursor);
        }
        return rows.getResultSet();
    }

    public function next():Null<Dynamic> {
        if (page == null || !page.hasNext()) {
            if (page != null && pageCount < BATCH) {
                return null;
            }
            page = nextPage();
            pageCount = 0;
            if (!page.hasNext()) {
                return null;
            }
        }
        var row = page.next();
        pageCount++;
        cursor = [];
        for (index in 0...table.primary.length) {
            var key = table.primary[index];
            var value:Dynamic = Reflect.field(row, key);
            if (value == null) {
                throw new Exception('Table ${table.name} contains an empty primary key.');
            }
            if (value is String && numericKeys[index]) {
                var number:String = value;
                value = new BigDecimal(number);
            }
            cursor.push(value);
        }
        transform(row);
        return row;
    }

    public override function readBytes(target:Bytes, position:Int, length:Int):Int {
        if (length == 0) {
            return 0;
        }
        if (offset == buffer.length) {
            var row = next();
            if (row == null) {
                throw new Eof();
            }
            var values = [for (name in columns) Reflect.field(row, name)];
            var data = Bytes.ofString(Json.stringify(values,
                (_, value) -> value is Bytes ? {base64: Base64.encode(cast value)} : value));
            if (data.length > BackupContent.MAX_RECORD) {
                throw new Exception('A record in ${table.name} exceeds the backup size limit.');
            }
            var framed = new BytesOutput();
            framed.bigEndian = true;
            framed.writeInt32(data.length);
            framed.write(data);
            buffer = framed.getBytes();
            offset = 0;
        }
        var count = Std.int(Math.min(length, buffer.length - offset));
        target.blit(position, buffer, offset, count);
        offset += count;
        return count;
    }

    public static function importTable(storage:StorageDisk, table:BackupTableDefinition,
            query:Void->QueryBuilder<Dynamic>, sqlite:Bool):Void {
        var file = path(table.name);
        var remaining = storage.size(file);
        var source = storage.readStream(file);
        source.bigEndian = true;
        try {
            while (remaining > 0) {
                if (remaining < 4) {
                    throw new Exception('Table ${table.name} contains an incomplete record.');
                }
                var length = source.readInt32();
                remaining -= 4;
                if (length <= 0 || length > remaining || length > BackupContent.MAX_RECORD) {
                    throw new Exception('Table ${table.name} contains an invalid record length.');
                }
                var values:Dynamic = Json.parse(source.readString(length));
                remaining -= length;
                if (!(values is Array) || values.length != table.columns.length) {
                    throw new Exception('Table ${table.name} contains an invalid record.');
                }
                var record:Map<String, Dynamic> = [];
                for (index in 0...table.columns.length) {
                    var column = table.columns[index];
                    var value:Dynamic = values[index];
                    if (value != null && (column.kind == "blob" || column.kind == "longblob")) {
                        if (!(value.base64 is String)) {
                            throw new Exception('Table ${table.name} contains invalid binary data.');
                        }
                        value = Base64.decode(value.base64);
                    } else if (value != null
                        && !(value is String)
                        && !(value is Float)
                        && !(value is Int)
                        && !(value is Bool)) {
                        throw new Exception('Table ${table.name} contains an unsupported cell.');
                    }
                    if (sqlite && value is String && BackupTable.integer(column.kind)) {
                        var text:String = value;
                        if (Int64.toStr(Int64.parseString(text)) != text) {
                            throw new Exception('Table ${table.name} contains an integer outside the SQLite range.');
                        }
                    }
                    record.set(column.name, value);
                }
                query().insert(record);
            }
        } catch (failure:Dynamic) {
            source.close();
            throw failure;
        }
        source.close();
    }
}
#end
