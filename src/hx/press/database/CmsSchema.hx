package hx.press.database;

import hx.press.ContentCache;
import hx.well.database.schema.Blueprint;
import hx.well.facades.Schema;
import hx.press.model.Setting;

class CmsSchema {
    public static function up():Void {
        PluginSchema.up();
        var fields:Array<{name:String, add:Blueprint->Void}> = [
            {
                name: "content_type",
                add: table -> {
                    table.string("content_type").defaultValue("entry");
                }
            },
            {
                name: "version",
                add: table -> {
                    table.integer("version").defaultValue(1);
                }
            },
            {
                name: "author_id",
                add: table -> {
                    table.integer("author_id").defaultValue(0);
                }
            },
            {
                name: "seo_title",
                add: table -> {
                    table.string("seo_title").defaultValue("");
                }
            },
            {
                name: "seo_description",
                add: table -> {
                    table.text("seo_description").defaultValue("");
                }
            },
            {
                name: "scheduled_epoch",
                add: table -> {
                    table.double("scheduled_epoch").defaultValue(0);
                }
            },
            {
                name: "previous_status",
                add: table -> {
                    table.string("previous_status").defaultValue("draft");
                }
            }
        ];
        for (field in fields) {
            if (!Schema.hasColumn("content_items", field.name)) {
                Schema.table("content_items", field.add);
            }
        }
        if (!Schema.hasColumn("admins", "role")) {
            Schema.table("admins", table -> table.string("role").defaultValue("owner"));
        }
        if (!Schema.hasColumn("admins", "active")) {
            Schema.table("admins", table -> table.integer("active").defaultValue(1));
        }
        if (!Schema.hasTable("tags")) {
            Schema.create("tags", table -> {
                table.id();
                table.string("name");
                table.string("name_key").unique();
                table.string("slug").unique();
                table.text("description");
                table.timestamps();
            });
        }
        if (!Schema.hasTable("content_tags")) {
            Schema.create("content_tags", table -> {
                table.id();
                table.bigInteger("content_id").unsigned();
                table.bigInteger("tag_id").unsigned();
                table.unique(["content_id", "tag_id"]);
                table.index(["tag_id", "content_id"]);
                table.foreign("content_id").references("id").on("content_items").cascadeOnDelete();
                table.foreign("tag_id").references("id").on("tags").cascadeOnDelete();
            });
        }
        if (!Schema.hasTable("content_revisions")) {
            Schema.create("content_revisions", table -> {
                table.id();
                table.bigInteger("document_id").unsigned();
                table.integer("version");
                table.string("title");
                table.text("snapshot");
                table.integer("author_id");
                table.dateTime("created_at");
                table.unique(["document_id", "version"]);
                table.foreign("document_id").references("id").on("content_items").cascadeOnDelete();
            });
        }
        if (!Schema.hasTable("editor_drafts")) {
            Schema.create("editor_drafts", table -> {
                table.string("key").primary();
                table.bigInteger("document_id").unsigned().defaultValue(0);
                table.integer("user_id");
                table.string("kind");
                table.string("title");
                table.text("payload");
                table.integer("version").defaultValue(0);
                table.integer("base_version").defaultValue(0);
                table.double("expires_epoch");
                table.dateTime("updated_at");
                table.index(["user_id", "kind", "updated_at"]);
                table.index(["expires_epoch"]);
            });
        }
        if (!Schema.hasTable("media_assets")) {
            Schema.create("media_assets", table -> {
                table.id();
                table.string("filename").unique();
                table.string("title");
                table.text("alt");
                table.string("mime_type");
                table.integer("width");
                table.integer("height");
                table.integer("size");
                table.timestamps();
            });
        }
        MediaDependencySchema.up();
        if (!Schema.hasTable("cms_packages")) {
            Schema.create("cms_packages", table -> {
                table.string("id").primary();
                table.string("kind");
                table.string("slug");
                table.string("name");
                table.string("name_key");
                table.string("version");
                table.text("description");
                table.string("author");
                table.string("directory");
                table.text("manifest");
                table.text("last_error").defaultValue("");
                table.integer("enabled").defaultValue(0);
                table.integer("setting_count").defaultValue(0);
                table.text("settings");
                table.dateTime("installed_at");
                table.dateTime("updated_at");
                table.unique(["kind", "slug"]);
                table.index(["kind", "id"]);
                table.index(["enabled", "kind", "id"]);
            });
        }
        if (!Schema.hasTable("package_hooks")) {
            Schema.create("package_hooks", table -> {
                table.id();
                table.string("package_id");
                table.string("event");
                table.unique(["package_id", "event"]);
                table.index(["event", "package_id"]);
                table.foreign("package_id").references("id").on("cms_packages").cascadeOnDelete();
            });
        }
        if (!Schema.hasColumn("cms_packages", "restart_required")) {
            Schema.table("cms_packages",
                table -> table.integer("restart_required").defaultValue(0));
        }
        if (!Schema.hasTable("package_uploads")) {
            Schema.create("package_uploads", table -> {
                table.string("key").primary();
                table.integer("user_id");
                table.string("kind");
                table.string("directory");
                table.text("manifest");
                table.double("expires_epoch");
                table.index(["user_id", "expires_epoch"]);
            });
        }
        if (!Schema.hasTable("menu_links")) {
            Schema.create("menu_links", table -> {
                table.id();
                table.string("location");
                table.string("label");
                table.string("url");
                table.integer("position");
                table.integer("new_tab").defaultValue(0);
                table.bigInteger("content_id").unsigned().defaultValue(0);
                table.string("collection_key", 32).defaultValue("");
                table.timestamps();
                table.index(["location", "position", "id"]);
            });
        }
        if (!Schema.hasTable("activity_logs")) {
            Schema.create("activity_logs", table -> {
                table.id();
                table.integer("user_id");
                table.string("actor");
                table.string("action");
                table.string("entity");
                table.integer("entity_id");
                table.string("label");
                table.dateTime("created_at");
                table.index(["entity", "entity_id", "id"]);
            });
        }
        if (!Schema.hasIndex("content_items", "cms_documents_cursor")) {
            Schema.table("content_items",
                table -> table.index(["content_type", "status", "updated_at", "id"],
                    "cms_documents_cursor"));
        }
        if (!Schema.hasIndex("content_items", "cms_schedule_due")) {
            Schema.table("content_items",
                table -> table.index(["status", "scheduled_epoch", "id"], "cms_schedule_due"));
        }
        if (!Schema.hasIndex("content_items", "cms_author_cursor")) {
            Schema.table("content_items",
                table -> table.index(["author_id", "content_type", "status", "updated_at", "id"],
                    "cms_author_cursor"));
        }
        if (Setting.query.find("cms_schema_v1") == null) {
            Setting.query.create(["key" => "cms_schema_v1", "value" => "1"]);
            ContentCache.contentChanged();
        }
    }
}
