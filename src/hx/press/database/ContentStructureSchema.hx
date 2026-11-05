package hx.press.database;

import haxe.Json;
import hx.press.ContentCache;
import hx.press.SiteSettingsStore;
import hx.press.model.ContentType;
import hx.press.model.Setting;
import hx.well.facades.Schema;

/** Defaults describe the old collections; runtime behavior reads the stored definitions. */
class ContentStructureSchema {
    public static function up():Void {
        if (!Schema.hasTable("content_types")) {
            Schema.create("content_types", table -> {
                table.string("key", 32).primary();
                table.string("name", 100);
                table.string("singular", 80);
                table.text("description");
                table.string("icon", 40);
                table.string("admin_path", 80).unique();
                table.string("public_path", 60).unique();
                table.integer("public_visible").defaultValue(1);
                table.integer("has_archive").defaultValue(1);
                table.integer("enabled").defaultValue(1);
                table.integer("system").defaultValue(0);
                table.string("owner").defaultValue("");
                table.string("capability", 80).defaultValue("content");
                table.integer("position").defaultValue(10);
                table.string("template", 80);
                table.string("archive_template", 80);
                table.text("features");
                table.text("fields");
                table.text("labels");
                table.integer("minimum_title_length").defaultValue(1);
                table.integer("minimum_content_length").defaultValue(0);
                table.integer("minimum_excerpt_length").defaultValue(0);
                table.timestamps();
                table.index(["enabled", "position", "key"]);
                table.index(["owner", "enabled", "key"]);
            });
        }
        if (!Schema.hasTable("content_type_paths")) {
            Schema.create("content_type_paths", table -> {
                table.string("path", 60).primary();
                table.string("type_key", 32);
                table.index(["type_key"]);
            });
        }
        if (!Schema.hasTable("content_values")) {
            Schema.create("content_values", table -> {
                table.id();
                table.bigInteger("content_id").unsigned();
                table.string("field_key", 40);
                table.text("value");
                table.string("value_text", 240).defaultValue("");
                table.double("value_number").defaultValue(0);
                table.unique(["content_id", "field_key"]);
                table.index(["field_key", "value_text", "content_id"]);
                table.index(["field_key", "value_number", "content_id"]);
                table.foreign("content_id").references("id").on("content_items").cascadeOnDelete();
            });
        }
        seed("entry", "Content", "Content item", "content", "ContentDetail", 1, "file", [
            "body",
            "excerpt",
            "categories",
            "tags",
            "image",
            "seo",
            "featured",
            "reading_time",
            "revisions",
            "schedule"
        ], {
            create: "Create content",
            edit: "Edit content",
            save: "Save content",
            title: "Content title",
            description: "Manage, schedule and publish your content."
        });
        seed("page", "Pages", "Page", "pages", "Page", 0, "layers",
            ["body", "excerpt", "tags", "image", "seo", "revisions", "schedule"], {
                create: "Create a page",
                edit: "Edit page",
                save: "Save page",
                title: "Page title",
                description: "Build the permanent pages of your site."
            });
        if (Setting.query.find("content_structure_v1") == null) {
            for (index in ["posts_slug_unique", "content_items_slug_unique"]) {
                if (Schema.hasIndex("content_items", index)) {
                    Schema.table("content_items", table -> table.dropUnique(index));
                }
            }
            // Native SQLite column changes also remove an old inline UNIQUE constraint.
            Schema.table("content_items", table -> table.string("slug", 180).change());
            if (!Schema.hasIndex("content_items", "content_items_type_slug_unique")) {
                Schema.table("content_items",
                    table -> table.unique(["content_type", "slug"],
                        "content_items_type_slug_unique"));
            }
            Setting.query.create(["key" => "content_structure_v1", "value" => "1"]);
            ContentCache.contentChanged();
        }
    }

    static function seed(key:String, name:String, singular:String, path:String, template:String,
            archive:Int, icon:String, features:Array<String>, labels:Dynamic):Void {
        if (ContentType.query.where("key", key).exists()) {
            return;
        }
        ContentType.query.create([
            "key" => key,
            "name" => name,
            "singular" => singular,
            "description" => "",
            "admin_path" => path,
            "public_path" => path,
            "public_visible" => 1,
            "has_archive" => archive,
            "enabled" => 1,
            "system" => 1,
            "owner" => "",
            "icon" => icon,
            "position" => key == "entry" ? 0 : 1,
            "template" => template,
            "archive_template" => "ContentIndex",
            "features" => Json.stringify(features),
            "fields" => "[]",
            "labels" => Json.stringify(labels),
            "minimum_title_length" => 3,
            "minimum_content_length" => 30,
            "minimum_excerpt_length" => key == "entry" ? 10 : 0,
            "created_at" => SiteSettingsStore.timestamp(),
            "updated_at" => SiteSettingsStore.timestamp()
        ]);
        ContentCache.changed("structure");
    }
}
