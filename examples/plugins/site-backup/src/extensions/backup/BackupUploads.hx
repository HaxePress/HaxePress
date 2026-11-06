package extensions.backup;

#if jvm
import haxe.Exception;
import haxe.Json;
import haxe.crypto.Sha256;
import haxe.io.Bytes;
import haxe.io.Eof;
import haxe.io.Input;
import hx.press.CmsAccess;
import hx.press.http.BodyLimits;
import hx.press.install.Installation;
import hx.well.facades.Storage;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.ResponseBuilder;
import hx.well.http.ResponseStatic.abort;
import hx.well.internal.SecureToken;
import hx.well.route.Route;
import hx.well.storage.StorageDisk;
import hx.well.thread.MutexPool;

using hx.well.tools.RouteElementTools;

enum abstract BackupUploadPurpose(String) to String {
    var Verify = "verify";
    var Restore = "restore";
}

private typedef BackupUploadState = {
    var id:String;
    var size:Int;
    var chunkSize:Int;
    var expires:Float;
}

class BackupUploads {
    static inline var ROOT = "backup-uploads";
    static inline var CHUNK_BYTES = 1024 * 1024;
    static inline var LIFETIME = 15 * 60 * 1000;

    /** The body of a request that starts, finishes or cancels an upload. **/
    public static inline var CONTROL_BYTES = 4096;

    static final locks = new MutexPool();

    public static function register(path:String, purpose:BackupUploadPurpose):Void {
        Route.path(path).group(() -> {
            Route.post("", request -> begin(request, purpose))
                .attribute(BodyLimits.ATTRIBUTE, CONTROL_BYTES);
            Route.post("/{upload}/{index}", request -> chunk(request, purpose))
                .setStream(true)
                .attribute(BodyLimits.ATTRIBUTE, CHUNK_BYTES);
            Route.delete("/{upload}", request -> cancel(request, purpose))
                .attribute(BodyLimits.ATTRIBUTE, CONTROL_BYTES);
        });
    }

    static function scope(request:Request, purpose:BackupUploadPurpose):String {
        if (purpose == BackupUploadPurpose.Verify && !CmsAccess.can(SiteBackup.CAPABILITY)) {
            abort(403);
        }
        if (purpose == BackupUploadPurpose.Restore && !Installation.pending()) {
            abort(404);
        }
        var session = request.session.sessionKey;
        var owner = Sha256.encode(session);
        return '${ROOT}/${purpose}-${owner}';
    }

    static function begin(request:Request, purpose:BackupUploadPurpose):AbstractResponse {
        var directory = scope(request, purpose);
        var limit = BackupFormat.maxBytes();
        if (!request.validate(["size" => [Required, Int, Min(1), Max(limit)]])) {
            return error("Choose a backup within the upload size limit.", 422);
        }
        if (purpose == BackupUploadPurpose.Restore) {
            expire();
        }
        var size:Int = request.input("size");
        var state:BackupUploadState = {
            id: SecureToken.generate(32),
            size: size,
            chunkSize: Std.int(Math.min(CHUNK_BYTES, SiteBackupArchive.maxBytes())),
            expires: Date.now().getTime() + LIFETIME
        };
        var disk = Storage.disk("local");
        return locked(directory, () -> {
            disk.deleteDirectory(directory);
            disk.put('${directory}/upload.json', Json.stringify(state), "private");
            return ResponseBuilder.asJson({id: state.id, chunkSize: state.chunkSize}, 201)
                .header("Cache-Control", "private, no-store");
        });
    }

    static function chunk(request:Request, purpose:BackupUploadPurpose):AbstractResponse {
        var directory = scope(request, purpose);
        var id = request.route("upload");
        var position = request.route("index");
        var index = position != null
            && ~/^(0|[1-9][0-9]{0,8})$/.match(position) ? Std.parseInt(position) : null;
        var disk = Storage.disk("local");
        return locked(directory, () -> {
            var state = active(disk, directory, id);
            if (state == null) {
                return error("This backup upload is no longer available.", 404);
            }
            if (index == null || index >= parts(state)) {
                return error("The backup chunk index is invalid.", 422);
            }
            var expected = partSize(state, index);
            var input = new BackupInput(request.context.input, state.chunkSize);
            var pending = '${directory}/pending';
            try {
                disk.writeStream(pending, input, "private");
            } catch (failure:Dynamic) {
                input.close();
                throw failure;
            }
            input.close();
            if (input.count != expected) {
                disk.delete(pending);
                return error("The backup chunk has an invalid length.", 422);
            }
            disk.move(pending, partPath(directory, index));
            return ResponseBuilder.asJson({received: index})
                .header("Cache-Control", "private, no-store");
        });
    }

    static function cancel(request:Request, purpose:BackupUploadPurpose):AbstractResponse {
        var directory = scope(request, purpose);
        var id = request.route("upload");
        var disk = Storage.disk("local");
        return locked(directory, () -> {
            var state = readState(disk, directory);
            if (state != null && state.id == id) {
                disk.deleteDirectory(directory);
            }
            return ResponseBuilder.asJson({cancelled: true})
                .header("Cache-Control", "private, no-store");
        });
    }

    public static function assemble(request:Request, purpose:BackupUploadPurpose,
            target:StorageDisk, archive:String):Void {
        var directory = scope(request, purpose);
        var id:Dynamic = request.input("upload", "");
        var disk = Storage.disk("local");
        locked(directory, () -> {
            var state = id is String ? active(disk, directory, id) : null;
            if (state == null) {
                throw new Exception("This backup upload is no longer available.");
            }
            var count = parts(state);
            for (index in 0...count) {
                var path = partPath(directory, index);
                if (!disk.fileExists(path) || disk.size(path) != partSize(state, index)) {
                    throw new Exception("The backup upload is incomplete.");
                }
            }
            var stream = new BackupPartsInput(disk, directory, count);
            try {
                target.writeStream(archive, stream, "private");
            } catch (failure:Dynamic) {
                stream.close();
                throw failure;
            }
            stream.close();
            disk.deleteDirectory(directory);
            return true;
        });
    }

    public static function expire():Void {
        var disk = Storage.disk("local");
        var prefix = ~/^backup-uploads\/(verify|restore)-[0-9a-f]{64}$/;
        for (directory in disk.directories(ROOT)) {
            if (prefix.match(directory)) {
                locked(directory, () -> {
                    var state = readState(disk, directory);
                    if (state == null || state.expires <= Date.now().getTime()) {
                        disk.deleteDirectory(directory);
                    }
                    return true;
                });
            }
        }
    }

    static function active(disk:StorageDisk, directory:String, id:String):Null<BackupUploadState> {
        if (id == null || !~/^[A-Za-z0-9_-]{32}$/.match(id)) {
            return null;
        }
        var state = readState(disk, directory);
        return state != null && state.id == id
            && state.expires > Date.now().getTime() ? state : null;
    }

    static function readState(disk:StorageDisk, directory:String):Null<BackupUploadState> {
        var path = '${directory}/upload.json';
        return disk.fileExists(path) ? cast Json.parse(disk.get(path)) : null;
    }

    static function parts(state:BackupUploadState):Int {
        return Math.ceil(state.size / state.chunkSize);
    }

    static function partSize(state:BackupUploadState, index:Int):Int {
        return Std.int(Math.min(state.chunkSize, state.size - index * state.chunkSize));
    }

    public static function partPath(directory:String, index:Int):String {
        return '${directory}/part-${index}';
    }

    static function error(message:String, status:Int):AbstractResponse {
        return ResponseBuilder.asJson({error: message}, status)
            .header("Cache-Control", "private, no-store");
    }

    static function locked<T>(directory:String, action:Void->T):T {
        locks.acquire(directory);
        try {
            var result = action();
            locks.release(directory);
            return result;
        } catch (failure:Dynamic) {
            locks.release(directory);
            throw failure;
        }
    }
}

private class BackupPartsInput extends Input {
    final disk:StorageDisk;
    final directory:String;
    final count:Int;
    var index = 0;
    var current:Null<Input>;

    public function new(disk:StorageDisk, directory:String, count:Int) {
        this.disk = disk;
        this.directory = directory;
        this.count = count;
    }

    public override function readBytes(bytes:Bytes, offset:Int, length:Int):Int {
        if (length == 0) {
            return 0;
        }
        while (true) {
            if (current == null) {
                if (index == count) {
                    throw new Eof();
                }
                current = disk.readStream(BackupUploads.partPath(directory, index++));
            }
            try {
                return current.readBytes(bytes, offset, length);
            } catch (_:Eof) {
                close();
            }
        }
    }

    public override function close():Void {
        if (current != null) {
            current.close();
            current = null;
        }
    }
}
#end
