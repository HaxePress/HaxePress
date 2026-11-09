package hx.press.database;

import hx.well.facades.Schema;

/**
    The Translations page: one row for every text the site shows, with its
    source wording, and one row for each of its translations.
**/
class TranslationSchema {
    public static function up():Void {
        if (!Schema.hasTable("translation_texts")) {
            Schema.create("translation_texts", table -> {
                table.id();
                table.string("namespace", 80);
                table.text("key");
                // Keys are compared by their hash: MySQL compares text without case.
                table.string("key_hash", 32);
                table.string("origin", 16);
                table.string("audience", 8).defaultValue("site");
                table.text("source");
                table.integer("plural").defaultValue(0);
                table.string("language", 35).defaultValue("en");
                table.integer("unused").defaultValue(0);
                table.double("updated_epoch").defaultValue(0);
                table.unique(["namespace", "key_hash"]);
                table.index(["namespace", "origin", "id"]);
                table.index(["audience", "unused", "id"]);
            });
        }
        if (!Schema.hasTable("translations")) {
            Schema.create("translations", table -> {
                table.id();
                table.bigInteger("text_id").unsigned();
                table.string("language", 35);
                table.text("value");
                table.text("shipped");
                table.integer("outdated").defaultValue(0);
                table.bigInteger("updated_by").defaultValue(0);
                table.double("updated_epoch").defaultValue(0);
                table.unique(["text_id", "language"]);
                table.index(["language", "text_id"]);
                table.foreign("text_id").references("id").on("translation_texts").cascadeOnDelete();
            });
        }
    }
}
