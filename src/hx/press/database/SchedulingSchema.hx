package hx.press.database;

import hx.well.facades.Schema;

class SchedulingSchema {
    public static function up():Void {
        if (!Schema.hasTable("scheduled_jobs")) {
            Schema.create("scheduled_jobs", table -> {
                table.string("id", 104).primary();
                table.string("plugin_id", 36).nullable();
                table.string("job_key", 64);
                table.text("payload");
                table.integer("interval_seconds");
                table.integer("enabled").defaultValue(1);
                table.double("next_epoch");
                table.double("last_epoch").defaultValue(0);
                table.string("last_error", 500).defaultValue("");
                table.double("lease_until").defaultValue(0);
                table.string("run_token", 32).defaultValue("");
                table.index(["enabled", "next_epoch", "id"]);
                table.index(["plugin_id", "id"]);
            });
        }
        if (!Schema.hasTable("scheduled_backup_files")) {
            Schema.create("scheduled_backup_files", table -> {
                table.string("id", 32).primary();
                table.string("schedule_id", 104);
                table.double("created_epoch");
                table.string("cms_version", 64);
                table.integer("encrypted");
                table.integer("size");
                table.string("md5", 32);
                table.index(["schedule_id", "created_epoch", "id"]);
            });
        }
    }
}
