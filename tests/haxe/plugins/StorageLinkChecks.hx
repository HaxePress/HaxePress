package plugins;

import haxe.Exception;
import hx.well.facades.Storage;
import hx.well.storage.StorageDisk;
import php.Global;

/** PHP checks local disk paths with lstat; links below the root stay rejected. */
class StorageLinkChecks {
    static function check(value:Bool, message:String):Void {
        if (!value) {
            throw new Exception(message);
        }
    }

    static function rejected(action:Void->Void):Bool {
        try {
            action();
        } catch (error:Dynamic) {
            return true;
        }
        return false;
    }

    public static function run(work:StorageDisk):Void {
        work.makeDirectory("storage-links/root/real");
        work.makeDirectory("storage-links/outside");
        work.put("storage-links/outside/secret.txt", "secret");
        var root = work.path("storage-links/root");
        var disk = Storage.build({driver: "local", root: root, throw_errors: true});
        disk.put("real/file.txt", "text");
        check(disk.fileExists("real/file.txt") && disk.size("real/file.txt") == 4,
            "PHP storage reads a regular file");
        check(disk.directoryExists("real") && !disk.fileExists("real"), "PHP storage file kinds");
        check(!disk.fileExists("real/missing.txt") && !disk.fileExists("missing/deeper/file.txt"),
            "PHP storage reports missing files");
        check(!disk.fileExists("real/file.txt/child"), "PHP storage treats a file as a leaf");
        // Links are fixtures here; Storage has no API that creates them.
        Global.symlink('${root}/real/file.txt', '${root}/file-link');
        Global.symlink('${root}/real', '${root}/directory-link');
        Global.symlink(work.path("storage-links/outside"), '${root}/outside-link');
        Global.symlink('${root}/nowhere', '${root}/dangling');
        Global.symlink(work.path("storage-links/outside/secret.txt"), '${root}/real/escape.txt');
        check(rejected(() -> disk.fileExists("file-link")), "PHP storage rejects a file link");
        check(rejected(() -> disk.get("directory-link/file.txt")),
            "PHP storage rejects a directory link inside the root");
        check(rejected(() -> disk.get("outside-link/secret.txt")),
            "PHP storage rejects a link out of the root");
        check(rejected(() -> disk.fileExists("dangling")), "PHP storage rejects a dangling link");
        check(rejected(() -> disk.put("dangling/created.txt", "x")) && !disk.exists("nowhere"),
            "PHP storage does not write through a dangling link");
        check(rejected(() -> disk.get("real/escape.txt")), "PHP storage rejects a nested link");
        check(rejected(() -> disk.files("", true)), "PHP storage listings reject links");
        check(rejected(() -> disk.path("../outside/secret.txt")),
            "PHP storage rejects parent segments");
        Sys.println("PASS PHP storage: regular paths, missing entries, and file, directory, outside, dangling and nested links");
    }
}
