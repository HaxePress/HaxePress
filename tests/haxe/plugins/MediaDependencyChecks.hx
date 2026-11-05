package plugins;

import haxe.Exception;
import haxe.Json;
import hx.press.SiteSettingsStore;
import hx.press.media.MediaDependencies;
import hx.press.media.MediaDependencyMode;
import hx.press.media.MediaUsage;
import hx.press.model.MediaAsset;
import hx.press.model.MediaDependency;
import hx.press.model.MediaDependencySource;
import hx.press.plugins.PluginDatabase;
import hx.well.facades.Schema;
import hx.well.facades.Storage;
import hx.well.internal.SecureToken;
import hx.well.model.BaseModel;
import hx.well.model.BaseModelQuery;

class MediaDependencyChecks {
    static function used(mediaId:Int, filename:String):Bool {
        try {
            return MediaUsage.used(mediaId, filename);
        } catch (error:Exception) {
            throw new Exception(error.details());
        }
    }

    static function check(value:Bool, message:String):Void {
        if (!value) {
            throw new Exception(message);
        }
    }

    static function rejects(action:Void->Void, message:String):Void {
        var rejected = false;
        try {
            action();
        } catch (_:Dynamic) {
            rejected = true;
        }
        check(rejected, message);
    }

    public static function run(token:String):Void {
        var slug = "media-" + token;
        var owner = "plugin-" + slug;
        var dependencies = MediaDependencies.forPlugin(slug);
        var filename = SecureToken.generate(32) + ".webp";
        var disk = Storage.disk("media");
        disk.makeDirectory("");
        disk.put(filename, "Dependency fixture bytes");
        var asset = MediaAsset.query.create([
            "filename" => filename,
            "title" => "Native dependency probe",
            "alt" => "",
            "mime_type" => "image/webp",
            "width" => 1,
            "height" => 1,
            "size" => 24,
            "created_at" => SiteSettingsStore.timestamp(),
            "updated_at" => SiteSettingsStore.timestamp()
        ]);
        Schema.create("media_dependency_probe", table -> {
            table.id();
            table.integer("media_id");
            table.string("source").defaultValue("");
            table.index(["media_id"]);
        });
        dependencies.retain(asset.id, "gallery:1");
        check(used(asset.id, filename), "Persistent ID reference did not protect media");
        MediaDependencies.forPlugin("unrelated-" + token).forget("gallery:1");
        check(used(asset.id, filename), "Another owner released the reference");
        dependencies.forget("gallery:1");
        check(!used(asset.id, filename), "Released reference stayed active");
        var model = new MediaProbe();
        dependencies.watch("rows", model, "media_id", MediaDependencyMode.Id);
        var row = MediaProbe.query.create(["media_id" => asset.id, "source" => disk.url(filename)]);
        check(used(asset.id, filename), "Watched model ID did not protect media");
        row.delete();
        dependencies.watch("rows", model, "source", MediaDependencyMode.Url);
        row = MediaProbe.query.create([
            "media_id" => 0,
            "source" => "https://example.test" + disk.url(filename) + "?size=small"
        ]);
        check(used(asset.id, filename), "Absolute URL reference was missed");
        row.delete();
        MediaDependencySource.query.where("owner", owner)
            .update(["column_name" => "missing_column"]);
        rejects(() -> used(asset.id, filename), "Broken dependency checks authorized deletion");
        dependencies.watch("rows", model, "source", MediaDependencyMode.Text);
        check(!used(asset.id, filename), "Empty watched model still reported usage");
        Schema.create("media_cascade_probe", table -> {
            table.id();
            table.integer("media_id");
            table.foreign("media_id").references("id").on("media_assets").cascadeOnDelete();
        });
        var cascade = new MediaProbe();
        cascade.setTable("media_cascade_probe");
        var cascadeQuery = new BaseModelQuery<MediaProbe>(cascade);
        cascadeQuery.create(["media_id" => asset.id]);
        check(used(asset.id, filename),
            "An unregistered CASCADE relationship did not protect media");
        Schema.drop("media_cascade_probe");
        var database = new PluginDatabase(slug);
        database.put("nested", {gallery: ["https://example.test" + disk.url(filename) + "#image"]});
        check(used(asset.id, filename), "Nested plugin JSON was not retained");
        database.forget("nested");
        check(!used(asset.id, filename), "Removed plugin JSON retained a stale dependency");
        dependencies.withValue("encoded", {path: StringTools.urlEncode(disk.url(filename))},
            () -> true);
        check(used(asset.id, filename), "Encoded value did not protect media");
        dependencies.forget("encoded");
        rejects(() -> dependencies.withReferences("failed-write", [asset.id],
            () -> throw new Exception("Write failure")),
            "Failed writer did not propagate");
        check(used(asset.id, filename), "Failed writer released its reservation");
        dependencies.forget("failed-write");
        Schema.enableForeignKeyConstraints();
        dependencies.retain(asset.id, "foreign-key");
        #if !cpp
        // hxcpp's bundled SQLite repeats a constraint error while finalizing the next statement.
        // JVM/PHP verify rejection directly; C++ verifies the deletion guard before a write.
        rejects(() -> asset.delete(),
            "Database foreign key allowed a retained media row to be removed");
        #end
        check(used(asset.id, filename), "A retained asset passed the native deletion guard");
        dependencies.forget("foreign-key");
        MediaDependencySource.query.where("owner", owner).delete();
        MediaDependency.query.where("owner", owner).delete();
        Schema.drop("media_dependency_probe");
        check(!used(asset.id, filename), "Unused native asset remained protected");
        asset.delete();
        disk.delete(filename);
        Sys.println("PASS Native media dependencies: owner isolation, persistent IDs, model/URL/JSON sources, CASCADE detection, failed writes and fail-closed checks");
    }
}
