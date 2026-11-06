package hx.press.media;

import haxe.Exception;
import haxe.Json;
import hx.press.model.ContentItem;
import hx.press.model.ContentRevision;
import hx.press.model.ContentType;
import hx.press.model.ContentValue;
import hx.press.model.EditorDraft;
import hx.press.model.InstalledPackage;
import hx.press.model.MediaAsset;
import hx.press.model.MediaDependency;
import hx.press.model.MediaDependencySource;
import hx.press.model.MenuLink;
import hx.press.model.PluginValue;
import hx.press.model.Setting;
import hx.press.model.Tag;
import hx.well.database.Connection;
import hx.well.database.query.QueryBuilder;
import hx.well.database.schema.SchemaGrammar;
import hx.well.facades.Schema;
import hx.well.model.BaseModel;
import hx.press.packages.PackageManifest;
import hx.press.packages.PackageSettings;

typedef MediaDependencySourceRecord = {
    var key:String;
    var connection_name:String;
    var table_name:String;
    var column_name:String;
    var mode:String;
}

typedef MediaForeignSource = {
    var key:String;
    var table:String;
    var query:QueryBuilder<Dynamic>;
}

/** Deletion reads live predicates; a stale cache must never authorize removing an asset. */
class MediaUsage {
    public static function pattern(filename:String):String {
        var escaped = StringTools.replace(StringTools.replace(StringTools.replace(filename, "!",
            "!!"), "%", "!%"), "_", "!_");
        return '%${escaped}%';
    }

    public static function contentQuery(filename:String):QueryBuilder<ContentItem> {
        var match = pattern(filename);
        return ContentItem.query.where(fields -> {
            fields.whereLike("image", match)
                .orWhereLike("content", match)
                .orWhereLike("excerpt", match)
                .orWhereLike("title", match)
                .orWhereLike("image_alt", match)
                .orWhereLike("seo_title", match)
                .orWhereLike("seo_description", match);
        });
    }

    static function coreUsed(filename:String):Bool {
        var match = pattern(filename);
        var content = contentQuery(filename).select(["id"]);
        return content.exists()
            || ContentValue.query.select(["id"])
                .where(fields -> fields.whereLike("value", match).orWhereLike("value_text", match))
                .exists() || ContentRevision.query.select(["id"])
            .whereLike("snapshot", match).exists()
            || EditorDraft.query.select(["key"]).whereLike("payload", match).exists()
            || Setting.query.select(["key"]).whereLike("value", match).exists()
            || PluginValue.query.select(["id"]).whereLike("value", match).exists()
            || InstalledPackage.query.select(["id"])
                .where(fields -> fields.whereLike("settings", match).orWhereLike("manifest", match))
                .exists() || ContentType.query.select(["key"])
            .where(fields -> fields.whereLike("fields", match)
                .orWhereLike("labels", match)
                .orWhereLike("description", match))
            .exists() || MenuLink.query.select(["id"]).whereLike("url", match).exists()
            || Tag.query.select(["id"]).whereLike("description", match).exists();
    }

    public static function watchedSourceUsed(source:MediaDependencySourceRecord, mediaId:Int,
            filename:String):Bool {
        if (Connection.driver(source.connection_name) == null) {
            throw new Exception("The media reference connection is unavailable.");
        }
        var schema = Schema.connection(source.connection_name);
        if (!schema.hasTable(source.table_name)) {
            // A removed table contains no data; a disabled package with a retained table is checked.
            return false;
        }
        if (!schema.hasColumn(source.table_name, source.column_name)) {
            throw new Exception("The media reference column is unavailable.");
        }
        var model = new BaseModel<Dynamic>();
        model.setConnection(source.connection_name);
        model.setTable(source.table_name);
        var query = new QueryBuilder(model);
        switch (source.mode) {
            case "id":
                query.where(source.column_name, mediaId);
            case "url":
                query.whereLike(source.column_name, pattern(filename));
            case "filename":
                query.where(source.column_name, filename);
            case "text":
                query.whereLike(source.column_name, pattern(filename));
            default:
                throw new Exception("The media reference mode is unavailable.");
        }
        return query.exists();
    }

    static function watchedUsed(mediaId:Int, filename:String):Bool {
        var after = "";
        while (true) {
            var query = MediaDependencySource.query.select(["key", "connection_name", "table_name", "column_name", "mode"]);
            if (after != "") {
                query.where("key", ">", after);
            }
            var sources:Array<MediaDependencySourceRecord> = query.orderBy("key")
                .limit(32)
                .get()
                .map(model -> cast model.toObject());
            if (sources.length == 0) {
                return false;
            }
            for (source in sources) {
                if (watchedSourceUsed(source, mediaId, filename)) {
                    return true;
                }
                after = source.key;
            }
        }
    }

    static function privateSettingsUsed(filename:String):Bool {
        var after = "";
        while (true) {
            var query = InstalledPackage.query.select(["id", "manifest", "settings"])
                .whereLike("manifest", "%\"secret\"%");
            if (after != "") {
                query.where("id", ">", after);
            }
            var packages:Array<{id:String, manifest:String, settings:String}> = query.orderBy("id")
                .limit(32)
                .get()
                .map(model -> cast model.toObject());
            if (packages.length == 0) {
                return false;
            }
            for (item in packages) {
                var manifest = PackageManifest.parse(item.manifest);
                var values = PackageSettings.values(manifest, item.settings, true);
                if (Json.stringify(values).indexOf(filename) >= 0) {
                    return true;
                }
                after = item.id;
            }
        }
    }

    public static function foreignSources(mediaId:Int):Array<MediaForeignSource> {
        var sources:Array<MediaForeignSource> = [];
        for (table in Schema.getTableListing()) {
            for (reference in Schema.getForeignKeys(table)) {
                if (SchemaGrammar.asciiLower(reference.foreignTable) != "media_assets") {
                    continue;
                }
                var columns = reference.foreignColumns;
                if (columns.length == 1 && columns[0] == "") {
                    columns = ["id"];
                }
                if (columns.length == 0 || columns.length != reference.columns.length) {
                    throw new Exception("The media foreign key metadata is incomplete.");
                }
                var asset = MediaAsset.query.select(columns).where("id", mediaId).first();
                var parent:Dynamic = asset == null ? null : asset.toObject();
                if (parent == null) {
                    throw new Exception("The media asset changed while checking dependencies.");
                }
                var model = new BaseModel<Dynamic>();
                model.setTable(table);
                var query = new QueryBuilder(model);
                var nullable = false;
                for (index in 0...columns.length) {
                    var value:Dynamic = Reflect.field(parent, columns[index]);
                    if (value == null) {
                        nullable = true;
                        break;
                    }
                    query.where(reference.columns[index], value);
                }
                if (!nullable) {
                    sources.push({key: '${table}:${reference.name}', table: table, query: query});
                }
            }
        }
        return sources;
    }

    static function foreignKeyUsed(mediaId:Int):Bool {
        for (source in foreignSources(mediaId)) {
            if (source.query.exists()) {
                return true;
            }
        }
        return false;
    }

    public static function used(mediaId:Int, filename:String):Bool {
        if (mediaId < 1 || !MediaReferences.validFilename(filename)) {
            throw new Exception("Choose a valid media library asset.");
        }
        try {
            return MediaDependency.query.select(["id"]).where("media_id", mediaId).exists()
                || coreUsed(filename)
                || privateSettingsUsed(filename)
                || foreignKeyUsed(mediaId)
                || watchedUsed(mediaId, filename);
        } catch (error:Exception) {
            throw new Exception("Media dependencies could not be verified. The image has not been deleted.",
                error);
        }
    }
}
