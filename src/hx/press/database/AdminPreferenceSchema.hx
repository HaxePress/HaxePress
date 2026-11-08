package hx.press.database;

import hx.well.facades.Schema;

/** Choices administrators make for their own view of the admin, one row per choice. */
class AdminPreferenceSchema {
    public static function up():Void {
        if (Schema.hasTable("admin_preferences")) {
            return;
        }
        Schema.create("admin_preferences", table -> {
            table.id();
            table.bigInteger("admin_id").unsigned();
            table.string("preference", 120);
            table.text("value");
            table.double("updated_epoch").defaultValue(0);
            table.unique(["admin_id", "preference"]);
            table.foreign("admin_id").references("id").on("admins").cascadeOnDelete();
        });
    }
}
