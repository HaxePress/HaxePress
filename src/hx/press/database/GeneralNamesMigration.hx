package hx.press.database;

import haxe.Exception;
import haxe.Json;
import hx.well.facades.Schema;
import hx.press.model.ActivityLog;
import hx.press.model.ContentItem;
import hx.press.model.ContentRevision;
import hx.press.model.EditorDraft;
import hx.press.model.InstalledPackage;
import hx.press.model.MenuLink;
import hx.press.model.Setting;

/** The only core boundary that understands the old publishing-specific schema. */
class GeneralNamesMigration {
    static inline var MARKER = "cms_general_names_v2";
    static inline var BATCH_SIZE = 50;

    public static function prepareSchema():Void {
        renameTable("posts", "content_items");
        renameTable("post_tags", "content_tags");
        if (Schema.hasTable("content_tags") && Schema.hasColumn("content_tags", "post_id")) {
            if (Schema.hasColumn("content_tags", "content_id")) {
                throw new Exception("Both legacy and canonical content reference columns exist. Resolve the naming migration before starting.");
            }
            Schema.table("content_tags", table -> table.renameColumn("post_id", "content_id"));
        }
        if (Schema.hasTable("content_items")) {
            var indexes = [
                "posts_status_published_at_index" => "content_items_status_published_at_index",
                "posts_status_date_cursor" => "content_items_status_date_cursor",
                "posts_status_category_date_cursor" => "content_items_status_category_date_cursor",
                "posts_featured_date_cursor" => "content_items_featured_date_cursor",
                "posts_updated_cursor" => "content_items_updated_cursor",
                "posts_status_updated_cursor" => "content_items_status_updated_cursor",
                "posts_category_lookup" => "content_items_category_lookup"
            ];
            renameIndexes("content_items", indexes);
        }
        if (Schema.hasTable("content_tags")) {
            renameIndexes("content_tags", [
                "post_tags_post_id_tag_id_unique" => "content_tags_content_id_tag_id_unique",
                "post_tags_tag_id_post_id_index" => "content_tags_tag_id_content_id_index"
            ]);
        }
    }

    static function renameTable(previous:String, current:String):Void {
        if (!Schema.hasTable(previous)) {
            return;
        }
        if (Schema.hasTable(current)) {
            throw new Exception("Both legacy and canonical content tables exist. Resolve the naming migration before starting.");
        }
        Schema.rename(previous, current);
    }

    static function renameIndexes(tableName:String, indexes:Map<String, String>):Void {
        for (previous => current in indexes) {
            if (Schema.hasIndex(tableName, previous) && !Schema.hasIndex(tableName, current)) {
                Schema.table(tableName, table -> table.renameIndex(previous, current));
            }
        }
    }

    public static function up():Void {
        if (Setting.query.where("key", MARKER).exists()) {
            return;
        }
        ContentItem.query.where("content_type", "post").update(["content_type" => "entry"]);
        ActivityLog.query.where("entity", "post").update(["entity" => "entry"]);
        migrateWorkingCopies();
        migrateRevisions();
        migrateNavigation();
        migrateFactorySettings();
        migrateBundledSettings();
        var previous = Setting.query.where("key", "managed_post_images_v1");
        if (previous.exists() && !Setting.query.where("key", "managed_content_images_v1")
            .exists()) {
            previous.update(["key" => "managed_content_images_v1"]);
        }
        Setting.query.insert(["key" => MARKER, "value" => "2.0.0"]);
    }

    static function migrateWorkingCopies():Void {
        while (true) {
            var rows = EditorDraft.query.select(["key", "kind", "payload"])
                .where("kind", "post")
                .orderBy("key")
                .limit(BATCH_SIZE)
                .get();
            if (rows.length == 0) {
                break;
            }
            for (row in rows) {
                var key = StringTools.replace(row.key, "-post-", "-entry-");
                if (key != row.key && EditorDraft.query.where("key", key).exists()) {
                    throw new Exception("A legacy working copy conflicts with an existing canonical copy. Both copies were retained.");
                }
                var payload:Dynamic = Json.parse(row.payload);
                if (Reflect.field(payload, "content_type") == "post") {
                    Reflect.setField(payload, "content_type", "entry");
                }
                row.update(["key" => key, "kind" => "entry", "payload" => Json.stringify(payload)]);
            }
        }
    }

    static function migrateRevisions():Void {
        var after = 0;
        while (true) {
            var rows = ContentRevision.query.select(["id", "snapshot"])
                .where("id", ">", after)
                .orderBy("id")
                .limit(BATCH_SIZE)
                .get();
            if (rows.length == 0) {
                break;
            }
            for (row in rows) {
                var snapshot:Dynamic = Json.parse(row.snapshot);
                if (Reflect.field(snapshot, "content_type") == "post") {
                    Reflect.setField(snapshot, "content_type", "entry");
                    row.update(["snapshot" => Json.stringify(snapshot)]);
                }
                after = row.id;
            }
        }
    }

    static function migrateNavigation():Void {
        var after = 0;
        while (true) {
            var rows = MenuLink.query.select(["id", "label", "url"])
                .where("id", ">", after)
                .orderBy("id")
                .limit(BATCH_SIZE)
                .get();
            if (rows.length == 0) {
                break;
            }
            for (row in rows) {
                var values:Map<String, Dynamic> = [];
                if (row.url == "/journal" || StringTools.startsWith(row.url, "/journal?")) {
                    values.set("url", '/content${row.url.substr(8)}');
                } else if (StringTools.startsWith(row.url, "/story/")) {
                    values.set("url", '/content/${row.url.substr(7)}');
                } else if (StringTools.startsWith(row.url, "/p/")) {
                    values.set("url", '/pages/${row.url.substr(3)}');
                } else if (StringTools.startsWith(row.url, "/tag/")) {
                    values.set("url", '/tags/${row.url.substr(5)}');
                }
                if (row.label == "The journal") {
                    values.set("label", "Content");
                } else if (row.label == "About me") {
                    values.set("label", "About");
                }
                if (values.keys().hasNext()) {
                    row.update(values);
                }
                after = row.id;
            }
        }
    }

    static function replaceSetting(key:String, previous:String, current:String):Void {
        Setting.query.where("key", key).where("value", previous).update(["value" => current]);
    }

    static function migrateFactorySettings():Void {
        var name = Setting.query.find("site_name");
        if (name == null || name.value.toLowerCase() != "fieldnotes") {
            return;
        }
        name.update(["value" => "HaxePress"]);
        replaceSetting("author_name", "Alex Morgan", "Site administrator");
        replaceSetting("description",
            "A personal journal on living thoughtfully, going places, and finding inspiration in the everyday.",
            "Create, organize and publish your content.");
        replaceSetting("author_bio",
            "A collector of little moments. I write about places, spaces, and the everyday things that make life feel a little richer.",
            "Manage your site, content and media with HaxePress.");
    }

    static function migrateBundledSettings():Void {
        var installed = InstalledPackage.query.where("id", "plugin-reading-companion")
            .limit(1)
            .first();
        if (installed == null) {
            return;
        }
        var values:Dynamic = Json.parse(installed.settings);
        var manifest:Dynamic = Json.parse(installed.manifest);
        if (!Reflect.hasField(values, "article_note")) {
            return;
        }
        if (!Reflect.hasField(values, "content_note")) {
            Reflect.setField(values, "content_note", Reflect.field(values, "article_note"));
        }
        Reflect.deleteField(values, "article_note");
        var fields:Array<Dynamic> = manifest.fields;
        for (field in fields) {
            if (field.key == "article_note") {
                field.key = "content_note";
            }
        }
        installed.update(["settings" => Json.stringify(values), "manifest" => Json.stringify(manifest)]);
    }
}
