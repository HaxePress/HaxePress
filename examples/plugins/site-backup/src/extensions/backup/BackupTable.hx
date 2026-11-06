package extensions.backup;

#if jvm
import haxe.Exception;
import haxe.crypto.Md5;
import hx.well.database.query.QueryIdentifier;
import hx.well.database.schema.Blueprint;
import hx.well.database.schema.ForeignKeyInfo;
import hx.well.database.schema.SchemaBuilder;
import hx.well.database.schema.SchemaGrammar;

typedef BackupColumn = {
    var name:String;
    var kind:String;
    var size:Int;
    var scale:Int;
    var nullable:Bool;
    var unsigned:Bool;
    var increment:Bool;
    var current:Bool;
    var defaultValue:Null<String>;
}

typedef BackupIndex = {
    var name:String;
    var columns:Array<String>;
    var unique:Bool;
}

typedef BackupTableDefinition = {
    var name:String;
    var columns:Array<BackupColumn>;
    var primary:Array<String>;
    var indexes:Array<BackupIndex>;
    var foreign:Array<ForeignKeyInfo>;
}

class BackupTable {
    public static inline var MAX_TABLES = 512;
    static final TYPES = [
        "tinyint",
        "smallint",
        "mediumint",
        "int",
        "bigint",
        "boolean",
        "double",
        "decimal",
        "varchar",
        "char",
        "text",
        "mediumtext",
        "longtext",
        "date",
        "datetime",
        "time",
        "timestamp",
        "year",
        "json",
        "blob",
        "longblob"
    ];
    static final ACTIONS = ["NO ACTION", "RESTRICT", "CASCADE", "SET NULL"];

    public static function read(schema:SchemaBuilder, name:String,
            sqlite:Bool):BackupTableDefinition {
        var columns:Array<BackupColumn> = [];
        var primary:Array<String> = [];
        var indexMap:Map<String, BackupIndex> = [];
        for (row in schema.getColumnDetails(name)) {
            var extra = sqlite ? "" : SchemaGrammar.asciiLower(Std.string(row.extra));
            if ((sqlite && number(row.hidden) != 0)
                || extra.indexOf("virtual generated") >= 0
                || extra.indexOf("stored generated") >= 0
                || extra.indexOf("on update") >= 0) {
                throw new Exception('Table ${name} contains nonportable columns.');
            }
            var column = readColumn(row, sqlite, extra);
            columns.push(column);
            if (sqlite && number(row.pk) > 0) {
                primary[number(row.pk) - 1] = column.name;
            }
        }
        if (sqlite && primary.length == 1) {
            for (column in columns) {
                if (column.name == primary[0] && column.kind == "bigint") {
                    column.increment = true;
                    column.unsigned = true;
                }
            }
        }
        for (row in schema.getIndexDetails(name)) {
            if (number(row.unsupported) != 0) {
                throw new Exception('Table ${name} contains a nonportable index.');
            }
            if (number(row.primary_key) != 0) {
                if (!sqlite) {
                    primary.push(row.column_name);
                }
                continue;
            }
            var index:BackupIndex = indexMap.get(row.name);
            if (index == null) {
                index = {name: row.name, columns: [], unique: number(row.unique_key) != 0};
                indexMap.set(row.name, index);
            }
            index.columns.push(row.column_name);
        }
        var indexes:Array<BackupIndex> = [];
        for (index in indexMap) {
            if (StringTools.startsWith(index.name, "sqlite_autoindex_")) {
                index.name = '${name}_${index.columns.join("_")}_unique';
            }
            index.name = fitName(index.name);
            indexes.push(index);
        }
        indexes.sort((a, b) -> Reflect.compare(a.name, b.name));
        var foreign = schema.getForeignKeys(name);
        for (key in foreign) {
            if (sqlite) {
                key.name = fitName('${name}_${key.columns.join("_")}_foreign');
            }
        }
        var definition = {
            name: name,
            columns: columns,
            primary: primary,
            indexes: indexes,
            foreign: foreign
        };
        validate(definition);
        return definition;
    }

    static function readColumn(row:Dynamic, sqlite:Bool, extra:String):BackupColumn {
        var declared = SchemaGrammar.asciiLower(Std.string(row.type));
        var kind = switch (declared.split("(")[0]) {
            case "integer": "bigint";
            case "real", "float", "double": "double";
            case "numeric", "decimal": "decimal";
            case "tinyint" if (declared == "tinyint(1)"): "boolean";
            case "text" if (sqlite): "longtext";
            case "blob" if (sqlite): "longblob";
            case "tinyblob", "mediumblob", "longblob": "longblob";
            case "tinytext": "text";
            case other: other;
        };
        var size = 0;
        var scale = 0;
        if (kind == "varchar" || kind == "char") {
            if (sqlite) {
                var length = ~/\((\d+)\)/;
                size = length.match(declared) ? number(length.matched(1)) : 255;
            } else {
                size = number(row.max_length);
            }
        } else if (kind == "decimal") {
            size = sqlite ? 65 : number(row.numeric_precision);
            scale = sqlite ? 30 : number(row.numeric_scale);
        }
        var rawDefault:Dynamic = sqlite ? row.dflt_value : row.default_value;
        var defaultValue = rawDefault == null ? null : Std.string(rawDefault);
        var current = false;
        if (defaultValue != null && (sqlite || extra.indexOf("default_generated") >= 0)) {
            var literal = StringTools.trim(defaultValue);
            while (StringTools.startsWith(literal, "(") && StringTools.endsWith(literal, ")")) {
                literal = StringTools.trim(literal.substring(1, literal.length - 1));
            }
            if (!sqlite) {
                literal = ~/^_[A-Za-z0-9_]+/.replace(literal, "");
                if (StringTools.startsWith(literal, "\\'")) {
                    literal = mysqlUnescape(literal);
                }
            }
            var quoted = sqlite ? ~/^'(?:[^']|'')*'$/ : ~/^'(?:[^'\\]|''|\\.)*'$/;
            if (~/^current_timestamp(\(\))?$/i.match(literal)) {
                current = true;
                defaultValue = null;
            } else if (SchemaGrammar.asciiLower(literal) == "null") {
                defaultValue = null;
            } else if (quoted.match(literal)) {
                defaultValue = StringTools.replace(literal.substring(1, literal.length - 1), "''",
                    "'");
                if (!sqlite) {
                    defaultValue = mysqlUnescape(defaultValue);
                }
            } else if (~/^-?\d+(\.\d+)?([eE][+-]?\d+)?$/.match(literal)) {
                defaultValue = literal;
            } else {
                throw new Exception('Column ${row.name} contains a nonportable default.');
            }
        }
        return {
            name: row.name,
            kind: kind,
            size: size,
            scale: scale,
            nullable: sqlite ? number(Reflect.field(row,
                "notnull")) == 0 && number(row.pk) == 0 : row.nullable == "YES",
            unsigned: !sqlite && Std.string(row.declared_type).indexOf("unsigned") >= 0,
            increment: extra.indexOf("auto_increment") >= 0,
            current: current,
            defaultValue: defaultValue
        };
    }

    static function mysqlUnescape(value:String):String {
        var escape = ~/\\(.)/g;
        return escape.map(value, match -> switch (match.matched(1)) {
            case "0": "\x00";
            case "b": "\x08";
            case "n": "\n";
            case "r": "\r";
            case "t": "\t";
            case "Z": "\x1a";
            case "\\", "'", '"': match.matched(1);
            case _: throw new Exception("The backup contains an unsupported MySQL default escape.");
        });
    }

    public static function validate(table:BackupTableDefinition):Void {
        if (!identifier(table.name)
            || StringTools.startsWith(SchemaGrammar.asciiLower(table.name), "sqlite_")
            || table.columns.length == 0
            || table.columns.length > 128
            || table.primary.length == 0
            || table.indexes.length > 128
            || table.foreign.length > 128) {
            throw new Exception("The backup contains an invalid or unsupported table definition.");
        }
        var names:Map<String, Bool> = [];
        for (column in table.columns) {
            var name = SchemaGrammar.asciiLower(column.name);
            if (!identifier(column.name)
                || names.exists(name)
                || !TYPES.contains(column.kind)
                || column.size < 0
                || column.size > 16383
                || column.scale < 0
                || column.scale > 30
                || (column.increment
                    && (table.primary.length != 1 || table.primary[0] != column.name
                        || !integer(column.kind)))
                || ((column.kind == "varchar" || column.kind == "char") && column.size < 1)
                || (column.kind == "decimal"
                    && (column.size < 1 || column.size > 65 || column.scale > column.size))
                || (column.defaultValue != null && !(column.defaultValue is String))) {
                throw new Exception('Column ${table.name}.${column.name} has an invalid or unsupported ${column.kind} definition.');
            }
            names.set(name, true);
        }
        var exact = table.columns.map(column -> column.name);
        requireColumns(table.primary, exact);
        for (index in table.indexes) {
            if (!identifier(index.name)) {
                throw new Exception("The backup contains an invalid index.");
            }
            requireColumns(index.columns, exact);
        }
        for (foreign in table.foreign) {
            if (!identifier(foreign.name)
                || !identifier(foreign.foreignTable)
                || foreign.columns.length != foreign.foreignColumns.length
                || !ACTIONS.contains(foreign.onDelete)
                || !ACTIONS.contains(foreign.onUpdate)) {
                throw new Exception("The backup contains an invalid foreign key.");
            }
            requireColumns(foreign.columns, exact);
        }
    }

    public static function requireColumns(columns:Array<String>, available:Array<String>):Void {
        if (columns.length == 0 || columns.length > 32) {
            throw new Exception("The backup contains an invalid key.");
        }
        var seen:Map<String, Bool> = [];
        for (column in columns) {
            if (!available.contains(column) || seen.exists(column)) {
                throw new Exception("The backup key references an invalid column.");
            }
            seen.set(column, true);
        }
    }

    public static function create(schema:SchemaBuilder, definition:BackupTableDefinition,
            mysql:Bool, created:Void->Void):Void {
        schema.createTracked(definition.name, table -> {
            if (mysql) {
                table.engine("InnoDB").charset("utf8mb4").collation("utf8mb4_bin");
            }
            var increment = false;
            for (column in definition.columns) {
                var field = switch (column.kind) {
                    case "tinyint": table.tinyInteger(column.name);
                    case "smallint": table.smallInteger(column.name);
                    case "mediumint": table.mediumInteger(column.name);
                    case "int": table.integer(column.name);
                    case "bigint": table.bigInteger(column.name);
                    case "boolean": table.boolean(column.name);
                    case "double": table.double(column.name);
                    case "decimal": table.decimal(column.name, column.size, column.scale);
                    case "char": table.char(column.name, column.size);
                    case "varchar": table.string(column.name, column.size);
                    case "text": table.text(column.name);
                    case "mediumtext": table.mediumText(column.name);
                    case "longtext": table.longText(column.name);
                    case "date": table.date(column.name);
                    case "datetime": table.dateTime(column.name);
                    case "time": table.time(column.name);
                    case "timestamp": table.timestamp(column.name);
                    case "year": table.year(column.name);
                    case "json": table.json(column.name);
                    case "blob", "longblob": table.binary(column.name);
                    case _: throw new Exception("The backup contains an unsupported column type.");
                };
                if (column.kind == "longblob") {
                    field.length = 16777216;
                }
                field.nullable(column.nullable);
                if (column.unsigned) {
                    field.unsigned();
                }
                if (column.increment) {
                    field.autoIncrement();
                    increment = true;
                }
                if (column.current) {
                    field.useCurrent();
                } else if (column.defaultValue != null) {
                    field.defaultValue(column.defaultValue);
                }
            }
            if (!increment) {
                table.primary(definition.primary);
            }
            for (index in definition.indexes) {
                if (index.unique) {
                    table.unique(index.columns, index.name);
                } else {
                    table.index(index.columns, index.name);
                }
            }
            if (!mysql) {
                addForeign(table, definition.foreign);
            }
        }, created);
    }

    public static function addForeign(table:Blueprint, keys:Array<ForeignKeyInfo>):Void {
        for (key in keys) {
            table.foreign(key.columns, key.name)
                .references(key.foreignColumns)
                .on(key.foreignTable)
                .onDelete(key.onDelete)
                .onUpdate(key.onUpdate);
        }
    }

    public static function textColumns(table:BackupTableDefinition):Array<String> {
        return [
            for (column in table.columns)
                if (integer(column.kind)
                    || ["decimal", "date", "datetime", "time", "timestamp"].contains(column.kind))
                    column.name
        ];
    }

    public static function integer(kind:String):Bool {
        return ["tinyint", "smallint", "mediumint", "int", "bigint", "year"].contains(kind);
    }

    public static function identifier(name:String):Bool {
        return QueryIdentifier.isValid(name) && name.length <= 64;
    }

    static function fitName(name:String):String {
        return name.length <= 64 ? name : '${name.substr(0, 55)}_${Md5.encode(name).substr(0, 8)}';
    }

    static function number(value:Dynamic):Int {
        if (value is Bool) {
            return (cast value : Bool) ? 1 : 0;
        }
        return Std.parseInt(Std.string(value)) ?? 0;
    }
}
#end
