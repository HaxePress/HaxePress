package hx.press.media;

import haxe.Exception;
import haxe.Json;
import hx.press.CmsAccess;
import hx.press.ContentCache;
import hx.press.content.ContentTypes;
import hx.press.i18n.I18n;
import hx.press.model.ContentItem;
import hx.press.model.ContentRevision;
import hx.press.model.ContentType;
import hx.press.model.ContentValue;
import hx.press.model.EditorDraft;
import hx.press.model.InstalledPackage;
import hx.press.model.MediaDependency;
import hx.press.model.MediaDependencySource;
import hx.press.model.MenuLink;
import hx.press.model.PluginValue;
import hx.press.model.Setting;
import hx.press.model.Tag;
import hx.press.packages.PackageManifest;
import hx.press.packages.PackageSettings;
import hx.well.database.query.QueryBuilder;

typedef MediaReference = {
    var id:String;
    var type:String;
    var title:String;
    var detail:String;
    var href:Null<String>;
    var restricted:Bool;
}

typedef MediaReferencePage = {
    var items:Array<MediaReference>;
    var next:Null<String>;
    var verified:Bool;
}

/** A live, bounded list of locations; response records never contain article bodies or settings values. */
class MediaReferenceReport {
    public static inline var PAGE_SIZE = 20;
    static inline var BATCH_SIZE = 32;
    static final sources = [
        "content",
        "fields",
        "revisions",
        "working",
        "settings",
        "plugin-values",
        "packages",
        "private-packages",
        "collections",
        "navigation",
        "tags",
        "retained",
        "watched",
        "foreign"
    ];

    static function primary(source:String):String {
        return
            ["working", "settings", "collections", "watched", "foreign"].contains(source) ? "key" : "id";
    }

    static function numeric(source:String):Bool {
        return [
            "content",
            "fields",
            "revisions",
            "plugin-values",
            "navigation",
            "tags",
            "retained"
        ].contains(source);
    }

    static function query(source:String, mediaId:Int, filename:String):QueryBuilder<Dynamic> {
        var match = MediaUsage.pattern(filename);
        return switch (source) {
            case "content": cast MediaUsage.contentQuery(filename)
                    .select(["id", "title", "content_type", "author_id", "status"]);
            case "fields": cast ContentValue.query.select(["id", "content_id", "field_key"])
                    .where(fields -> fields.whereLike("value", match)
                        .orWhereLike("value_text", match));
            case "revisions": cast ContentRevision.query.select(["id", "document_id", "version"])
                    .whereLike("snapshot", match);
            case "working": cast EditorDraft.query.select(["key", "document_id", "user_id", "kind", "title"])
                    .whereLike("payload", match);
            case "settings": cast Setting.query.select(["key"]).whereLike("value", match);
            case "plugin-values": cast PluginValue.query.select(["id", "plugin_id", "scope", "key"])
                    .whereLike("value", match);
            case "packages": cast InstalledPackage.query.select(["id", "name", "kind"])
                    .where(fields -> fields.whereLike("settings", match)
                        .orWhereLike("manifest", match));
            case "private-packages": cast InstalledPackage.query.select(["id", "name", "kind", "manifest", "settings"])
                    .whereLike("manifest", "%\"secret\"%");
            case "collections": cast ContentType.query.select(["key", "name"])
                    .where(fields -> fields.whereLike("fields", match)
                        .orWhereLike("labels", match)
                        .orWhereLike("description", match));
            case "navigation": cast MenuLink.query.select(["id", "label"])
                    .whereLike("url", match);
            case "tags": cast Tag.query.select(["id", "name"]).whereLike("description", match);
            case "retained": cast MediaDependency.query.select(["id", "owner", "reference_key", "label"])
                    .where("media_id", mediaId);
            case "watched": cast MediaDependencySource.query.select(["key", "owner", "label", "connection_name", "table_name", "column_name", "mode"]);
            default: throw new Exception("Choose a valid media reference source.");
        };
    }

    static function batch(source:String, mediaId:Int, filename:String,
            after:String):Array<Dynamic> {
        if (source == "foreign") {
            // Schema metadata is small; dependent table records remain behind SQL EXISTS predicates.
            var metadata = MediaUsage.foreignSources(mediaId);
            metadata.sort((left, right) -> Reflect.compare(left.key, right.key));
            var rows:Array<Dynamic> = [];
            for (entry in metadata) {
                if (entry.table != "media_dependencies" && (after == "" || entry.key > after)) {
                    rows.push({key: entry.key, table: entry.table, query: entry.query});
                    if (rows.length == BATCH_SIZE) {
                        break;
                    }
                }
            }
            return rows;
        }
        var records = query(source, mediaId, filename);
        var key = primary(source);
        if (after != "") {
            var value:Dynamic = numeric(source) ? Std.parseInt(after) : after;
            records.where(key, ">", value);
        }
        return records.orderBy(key).limit(BATCH_SIZE).get().map(model -> cast model.toObject());
    }

    static function reference(source:String, key:String, type:String, title:String,
            detail:String = "", href:String = null, permitted:Bool = true):MediaReference {
        return {
            id: source + ":" + key,
            type: type,
            title: permitted ? title : I18n.t("Restricted reference"),
            detail: permitted ? detail : I18n.t("Your account cannot view this record."),
            href: permitted ? href : null,
            restricted: !permitted
        };
    }

    static function document(id:Int):Dynamic {
        var document = ContentItem.query.select(["id", "title", "content_type", "author_id"])
            .where("id", id)
            .first();
        return document == null ? null : document.toObject();
    }

    static function contentReference(source:String, key:String, type:String, item:Dynamic,
            detail:String = ""):MediaReference {
        if (item == null) {
            return reference(source, key, type, I18n.t("Deleted content"), detail);
        }
        var permitted = CmsAccess.canCollection(item.content_type)
            && CmsAccess.canEdit(item.author_id);
        var href = ContentTypes.adminBase(item.content_type) + "/" + item.id + "/edit";
        return reference(source, key, type, item.title, detail, href, permitted);
    }

    static function packageReference(source:String, key:String, owner:String, type:String,
            detail:String = ""):MediaReference {
        var item:Null<{id:String, name:String, kind:String}> = ContentCache.remember("extensions",
            "reference-owner", [owner], () -> {
                var installed = InstalledPackage.query.select(["id", "name", "kind"])
                    .where("id", owner)
                    .first();
                return installed == null ? null : cast installed.toObject();
            });
        var title = item == null ? owner : item.name;
        var href = item == null ? null : "/admin/" + (item.kind == "theme" ? "themes" : "plugins");
        if (item != null && type == "Theme design") {
            href += "/" + item.id + "/design";
        }
        return reference(source, key, type, title, detail, href, CmsAccess.can("extensions"));
    }

    static function present(source:String, row:Dynamic, mediaId:Int,
            filename:String):Null<MediaReference> {
        var key = Std.string(Reflect.field(row, primary(source)));
        return switch (source) {
            case "content": contentReference(source, key, "Content", row, row.status);
            case "fields": contentReference(source, key, "Custom field", document(row.content_id),
                    row.field_key);
            case "revisions":
                contentReference(source, key, "Revision", document(row.document_id),
                    I18n.t("Revision {version}", ["version" => Std.string(row.version)]));
            case "working":
                var own = row.user_id == CmsAccess.current().id
                    && CmsAccess.canCollection(row.kind);
                var href = row.document_id > 0 ? ContentTypes.adminBase(row.kind)
                    + "/"
                    + row.document_id
                    + "/edit" : ContentTypes.adminBase(row.kind)
                    + "/new?draft="
                    + StringTools.urlEncode(row.key);
                reference(source, key, "Working copy", row.title, "", href, own);
            case "settings":
                var title = row.key == "site_logo" ? I18n.t("Site logo") : row.key;
                reference(source, key, "Site settings", title, "", "/admin/settings",
                    CmsAccess.can("settings"));
            case "plugin-values":
                packageReference(source, key, "plugin-" + row.plugin_id, "Plugin data",
                    row.scope + " / " + row.key);
            case "packages", "private-packages":
                if (source == "private-packages") {
                    var manifest = PackageManifest.parse(row.manifest);
                    var values = PackageSettings.values(manifest, row.settings, true);
                    if (Json.stringify(values).indexOf(filename) < 0) {
                        return null;
                    }
                }
                reference(source, key, "Package settings", row.name, "",
                    "/admin/"
                    + (row.kind == "theme" ? "themes" : "plugins")
                    + "/"
                    + row.id
                    + "/settings",
                    CmsAccess.can("extensions"));
            case "collections":
                reference(source, key, "Collection", row.name, "",
                    "/admin/content-types/" + StringTools.urlEncode(row.key) + "/edit",
                    CmsAccess.can("settings"));
            case "navigation":
                reference(source, key, "Navigation", row.label, "", "/admin/navigation",
                    CmsAccess.can("navigation"));
            case "tags":
                reference(source, key, "Tag", row.name, "",
                    "/admin/tags?q=" + StringTools.urlEncode(row.name), CmsAccess.can("taxonomy"));
            case "retained":
                var detail:String = row.label;
                if (!~/^value-[a-f0-9]{32}$/.match(row.reference_key)) {
                    detail = detail == "" ? row.reference_key : detail + " · " + row.reference_key;
                }
                var type = StringTools.startsWith(row.owner, "theme-")
                    && ["design-draft", "design-published"].contains(row.reference_key) ? "Theme design" : "Plugin dependency";
                packageReference(source, key, row.owner, type, detail);
            case "watched":
                if (!MediaUsage.watchedSourceUsed(cast row, mediaId, filename)) {
                    return null;
                }
                packageReference(source, key, row.owner, "Plugin data", row.label);
            case "foreign":
                var dependent:QueryBuilder<Dynamic> = row.query;
                if (!dependent.exists()) {
                    return null;
                }
                reference(source, key, "Database dependency", I18n.t("Database relationship"),
                    row.table, null, CmsAccess.can("settings"));
            default: null;
        };
    }

    public static function page(mediaId:Int, filename:String, start:String = "content",
            after:String = ""):MediaReferencePage {
        var sourceIndex = sources.indexOf(start);
        if (sourceIndex < 0
            || after.length > 200
            || ~/[\x00-\x1f\x7f]/.match(after)
            || (after != "" && numeric(start) && !~/^[0-9]{1,10}$/.match(after))) {
            throw new Exception("Choose a valid media reference cursor.");
        }
        var items:Array<MediaReference> = [];
        var resumeSource = start;
        var resumeKey = after;
        while (sourceIndex < sources.length) {
            var source = sources[sourceIndex];
            try {
                var rows = batch(source, mediaId, filename, after);
                for (row in rows) {
                    var item = present(source, row, mediaId, filename);
                    after = Std.string(Reflect.field(row, primary(source)));
                    if (item == null) {
                        continue;
                    }
                    if (items.length == PAGE_SIZE) {
                        var next = "/admin/media/"
                            + mediaId
                            + "/references?source="
                            + resumeSource
                            + "&after="
                            + StringTools.urlEncode(resumeKey);
                        return {items: items, next: next, verified: true};
                    }
                    items.push(item);
                    resumeSource = source;
                    resumeKey = after;
                }
                if (rows.length == BATCH_SIZE) {
                    continue;
                }
            } catch (_:Exception) {
                // An unavailable source is visible as an incomplete report, never as permission to delete.
                return {items: items, next: null, verified: false};
            }
            sourceIndex++;
            after = "";
        }
        return {items: items, next: null, verified: true};
    }
}
