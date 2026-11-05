package fixtures;

import haxe.Exception;
import haxe.ds.List;
import sys.db.ResultSet;

class GuardedResultSet implements ResultSet {
    public var length(get, null):Int;
    public var nfields(get, null):Int;

    var delegate:ResultSet;
    var allowedId:Null<Int>;
    var maximumRows:Null<Int>;
    var rowsRead:Int = 0;

    public function new(delegate:ResultSet, allowedId:Null<Int>, maximumRows:Null<Int> = null) {
        this.delegate = delegate;
        this.allowedId = allowedId;
        this.maximumRows = maximumRows;
    }

    function get_length():Int {
        return delegate.length;
    }

    function get_nfields():Int {
        return delegate.nfields;
    }

    public function hasNext():Bool {
        return delegate.hasNext();
    }

    public function next():Dynamic {
        var row = delegate.next();
        if (row != null) {
            rowsRead++;
            if (allowedId != null && (rowsRead > 1 || row.id != allowedId)) {
                throw new Exception("Test guard rejected an unrequested content item body");
            }
            if (maximumRows != null && rowsRead > maximumRows) {
                throw new Exception("Test guard rejected an oversized content summary result");
            }
        }
        return row;
    }

    public function results():List<Dynamic> {
        var rows = new List<Dynamic>();
        while (hasNext()) {
            rows.add(next());
        }
        return rows;
    }

    public function getResult(index:Int):String {
        return delegate.getResult(index);
    }

    public function getIntResult(index:Int):Int {
        return delegate.getIntResult(index);
    }

    public function getFloatResult(index:Int):Float {
        return delegate.getFloatResult(index);
    }

    public function getFieldsNames():Null<Array<String>> {
        return delegate.getFieldsNames();
    }
}
