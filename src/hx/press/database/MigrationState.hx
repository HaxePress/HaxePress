package hx.press.database;

import hx.press.BuildIdentity;
import hx.press.model.Setting;
#if php
import hx.well.facades.Storage;
import php.Const;
import php.Global;
import php.Resource;
#end

/**
    Records which build last migrated the database. PHP starts the
    application for each request, so it runs the migrations once per
    deployment instead of checking the whole schema on every request. A
    restored backup carries its own record and is migrated again.
**/
class MigrationState {
    static inline var KEY = "migrated_build";

    /** Runs `migrate` unless this build already migrated the database. **/
    public static function ensure(migrate:Void->Void):Void {
        #if php
        if (current()) {
            return;
        }
        // Requests run in separate processes; the first one migrates and the others wait.
        var disk = Storage.disk("local");
        disk.makeDirectory("");
        var opened = Global.fopen(disk.path("migrations.lock"), "c");
        if (opened == false) {
            throw "The migration lock file could not be opened.";
        }
        var lock:Resource = cast opened;
        Global.flock(lock, Const.LOCK_EX);
        try {
            if (!current()) {
                migrate();
                record();
            }
        } catch (error:Dynamic) {
            Global.flock(lock, Const.LOCK_UN);
            Global.fclose(lock);
            throw error;
        }
        Global.flock(lock, Const.LOCK_UN);
        Global.fclose(lock);
        #else
        migrate();
        #end
    }

    static function current():Bool {
        return Setting.query.where("key", KEY).where("value", BuildIdentity.id).exists();
    }

    static function record():Void {
        Setting.query.upsert(["key" => KEY, "value" => BuildIdentity.id], ["key"], ["value"]);
    }
}
