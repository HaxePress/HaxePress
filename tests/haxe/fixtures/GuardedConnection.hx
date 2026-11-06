package fixtures;

import haxe.Exception;
import haxe.Json;
import hx.well.facades.Environment;
import hx.well.http.RequestStatic;
import sys.db.Connection;
import sys.db.ResultSet;
import hx.well.facades.Storage;
import haxe.io.Path;

/** Observes native result metadata; never builds or rewrites database statements. */
class GuardedConnection implements Connection {
    var delegate:Connection;

    public function new(delegate:Connection) {
        this.delegate = delegate;
    }

    public function request(statement:String):ResultSet {
        var path = Environment.env("TEST_GUARD_PATH", "");
        var policy:Dynamic = {};
        if (path != "") {
            var disk = Storage.build({
                driver: "local",
                root: Path.directory(path),
                read_only: true
            });
            var filename = Path.withoutDirectory(path);
            if (disk.fileExists(filename)) {
                policy = disk.json(filename);
            }
        }
        if (policy.blockDatabase == true) {
            throw new Exception("Test guard rejected database access");
        }

        var result = delegate.request(statement);
        var fields = result.getFieldsNames();
        if (fields != null && policy.rejectFields != null) {
            var rejected:Array<String> = policy.rejectFields;
            for (field in rejected) {
                if (fields.contains(field)) {
                    throw new Exception('Test guard rejected result column ${field}');
                }
            }
        }
        if (policy.bodyPaths != null && fields != null && fields.contains("content")) {
            var request = RequestStatic.request();
            var requestPath = request == null ? "" : request.path;
            var allowedId:Null<Int> = Reflect.field(policy.bodyPaths, requestPath);
            if (allowedId == null) {
                throw new Exception("Test guard rejected content item body projection");
            }
            return new GuardedResultSet(result, allowedId);
        }
        if (policy.summaryLimits != null && fields != null && fields.contains("excerpt")) {
            var current = RequestStatic.request();
            var requestPath = current == null ? "" : current.path;
            var maximum:Null<Int> = Reflect.field(policy.summaryLimits, requestPath);
            if (maximum != null) {
                return new GuardedResultSet(result, null, maximum);
            }
        }
        return result;
    }

    public function close():Void {
        delegate.close();
    }

    public function escape(value:String):String {
        return delegate.escape(value);
    }

    public function quote(value:String):String {
        return delegate.quote(value);
    }

    public function addValue(buffer:StringBuf, value:Dynamic):Void {
        delegate.addValue(buffer, value);
    }

    public function lastInsertId():Int {
        return delegate.lastInsertId();
    }

    public function dbName():String {
        return delegate.dbName();
    }

    public function startTransaction():Void {
        delegate.startTransaction();
    }

    public function commit():Void {
        delegate.commit();
    }

    public function rollback():Void {
        delegate.rollback();
    }
}
