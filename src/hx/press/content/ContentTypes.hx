package hx.press.content;

import haxe.Exception;
import haxe.Json;
import hx.press.CategoryData;
import hx.press.access.Roles;
import hx.press.ContentCache;
import hx.press.Pagination;
import hx.press.Pagination.PageCursor;
import hx.press.SiteSettingsStore;
import hx.press.content.ContentTypeDefinition.ContentFieldDefinition;
import hx.press.content.ContentTypeDefinition.ContentTypeRecord;
import hx.press.content.ContentTypeDefinition.ContentTypeSummary;
import hx.press.data.QueryPage;
import hx.press.model.ContentItem;
import hx.press.model.ContentType;
import hx.press.model.ContentTypePath;
import hx.press.model.EditorDraft;
import hx.press.model.InstalledPackage;
import hx.press.validation.Slug;
import hx.well.database.query.QueryBuilder;
import hx.well.facades.DBStatic;

/** Shared definition queries for routing, editors, collections, themes and native plugins. */
class ContentTypes {
    public static inline var PAGE_SIZE = 20;
    public static inline var MAX_FIELDS = 32;
    public static final supportedFeatures = [
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
    ];
    public static final fieldKinds = ["text", "textarea", "number", "boolean", "date", "select", "image"];
    public static final summaryColumns = [
        "key",
        "name",
        "singular",
        "icon",
        "admin_path",
        "public_path",
        "public_visible",
        "enabled",
        "system",
        "owner",
        "capability",
        "position"
    ];
    static final columns = summaryColumns.concat([
        "description",
        "has_archive",
        "template",
        "archive_template",
        "features",
        "fields",
        "labels",
        "minimum_title_length",
        "minimum_content_length",
        "minimum_excerpt_length"
    ]);
    static final reservedPaths = [
        "admin",
        "api",
        "about",
        "build",
        "categories",
        "tags",
        "locale",
        "media",
        "storage",
        "extension-assets",
        "packages",
        "themes",
        "fonts",
        "images",
        "search",
        "journal",
        "story",
        "p",
        "tag"
    ];

    public static function validKey(key:String):Bool {
        return key != null && ~/^[a-z][a-z0-9_]{0,31}(?![\s\S])/.match(key);
    }

    public static function available(query:QueryBuilder<ContentType>):QueryBuilder<ContentType> {
        var owners = InstalledPackage.query.select(["id"])
            .where("kind", "plugin")
            .where("enabled", 1)
            .where("restart_required", 0);
        return query.where("enabled", 1).where(visibility -> {
            visibility.where("owner", "").orWhere(plugin -> plugin.whereInQuery("owner", owners));
        });
    }

    public static function publicKeys():QueryBuilder<ContentType> {
        return available(ContentType.query.select(["key"])).where("public_visible", 1);
    }

    public static function accessible(query:QueryBuilder<ContentType>,
            capabilities:Array<String>):QueryBuilder<ContentType> {
        available(query);
        if (!capabilities.contains("*")) {
            query.whereIn("capability", cast capabilities);
        }
        return query;
    }

    public static function revision():String {
        return '${ContentCache.revision("structure")}:${packageRevision()}';
    }

    static function packageRevision():String {
        return ContentCache.revision("extensions");
    }

    static function byKey(key:String, activeOnly:Bool):QueryBuilder<ContentType> {
        var query = ContentType.query.where("key", key);
        return activeOnly ? available(query) : query;
    }

    public static function exists(key:String, activeOnly:Bool = true):Bool {
        if (!validKey(key)) {
            return false;
        }
        return ContentCache.remember("structure", "type-exists",
            [key, activeOnly, packageRevision()], () -> byKey(key, activeOnly).exists());
    }

    public static function record(key:String, activeOnly:Bool = true):Null<ContentTypeRecord> {
        if (!validKey(key)) {
            return null;
        }
        return ContentCache.remember("structure", "type", [key, activeOnly, packageRevision()],
            () -> {
                var row = byKey(key, activeOnly).select(columns).first();
                return row == null ? null : cast row.toObject();
            });
    }

    public static function find(key:String, activeOnly:Bool = true):Null<ContentTypeDefinition> {
        var row = record(key, activeOnly);
        return row == null ? null : definition(row);
    }

    public static function byPath(path:String):Null<ContentTypeDefinition> {
        if (!Slug.valid(path)) {
            return null;
        }
        var row:ContentTypeRecord = ContentCache.remember("structure", "public-path",
            [path, packageRevision()], () -> {
                var current = available(ContentType.query.select(columns)).where("public_path",
                    path)
                    .where("public_visible", 1)
                    .first();
                if (current != null) {
                    return cast current.toObject();
                }
                var alias = ContentTypePath.query.select(["type_key"])
                    .where("path", path)
                    .limit(1)
                    .first();
                if (alias == null) {
                    return null;
                }
                var previous = available(ContentType.query.select(columns)).where("key",
                    alias.type_key)
                    .where("public_visible", 1)
                    .first();
                return previous == null ? null : cast previous.toObject();
            });
        return row == null ? null : definition(row);
    }

    public static function definition(row:ContentTypeRecord):ContentTypeDefinition {
        return {
            key: row.key,
            name: row.name,
            singular: row.singular,
            description: row.description,
            icon: row.icon,
            adminBase: '/admin/${row.admin_path}',
            publicBase: '/${row.public_path}',
            publicVisible: row.public_visible == 1,
            hasArchive: row.has_archive == 1,
            enabled: row.enabled == 1,
            system: row.system == 1,
            owner: row.owner,
            capability: row.capability,
            position: row.position,
            template: row.template,
            archiveTemplate: row.archive_template,
            features: Json.parse(row.features),
            fields: validateFields(Json.parse(row.fields)),
            labels: Json.parse(row.labels),
            minimumTitleLength: row.minimum_title_length,
            minimumContentLength: row.minimum_content_length,
            minimumExcerptLength: row.minimum_excerpt_length
        };
    }

    public static function supports(type:ContentTypeDefinition, feature:String):Bool {
        return type != null && type.features.contains(feature);
    }

    public static function publicInfo(type:ContentTypeDefinition):Dynamic {
        return {
            key: type.key,
            name: type.name,
            singular: type.singular,
            description: type.description,
            publicBase: type.publicBase,
            hasArchive: type.hasArchive,
            features: type.features,
            fields: [for (field in type.fields) if (field.publicVisible) field]
        };
    }

    public static function adminBase(key:String):String {
        if (validKey(key)) {
            var base = ContentCache.remember("structure", "admin-base", [key], () -> {
                var row = byKey(key, false).select(["admin_path"]).first();
                return row == null ? null : '/admin/${row.admin_path}';
            });
            if (base != null) {
                return base;
            }
        }
        return '/admin/collections/${StringTools.urlEncode(key)}';
    }

    public static function url(key:String, slug:String):String {
        if (!validKey(key)) {
            return "";
        }
        var base = ContentCache.remember("structure", "public-base", [key, packageRevision()],
            () -> {
                var row = byKey(key,
                    true).where("public_visible", 1).select(["public_path"]).first();
                return row == null ? null : '/${row.public_path}';
            });
        return base == null ? "" : '${base}/${StringTools.urlEncode(slug)}';
    }

    public static function navigation(selected:String = "",
            capabilities:Array<String> = null):Array<ContentTypeSummary> {
        var grants = capabilities ?? ["*"];
        var rows:Array<ContentTypeSummary> = ContentCache.remember("structure",
            "admin-navigation", [12, packageRevision(), grants], () -> {
                return accessible(ContentType.query.select(summaryColumns),
                    grants).orderBy("position")
                    .orderBy("key")
                    .limit(12)
                    .get()
                    .map(model -> cast model.toObject());
            });
        var hasSelected = selected == "";
        for (row in rows) {
            if (row.key == selected) {
                hasSelected = true;
                break;
            }
        }
        if (!hasSelected) {
            var selectedType = accessible(ContentType.query.select(summaryColumns),
                grants).where("key", selected).first();
            var extra:ContentTypeSummary = selectedType == null ? null : cast selectedType.toObject();
            if (extra != null) {
                rows = rows.concat([extra]);
            }
        }
        return rows;
    }

    static function filtered(search:String, author:Int = 0,
            capabilities:Array<String> = null):QueryBuilder<ContentType> {
        var query = ContentType.query.select(summaryColumns);
        if (capabilities != null && !capabilities.contains("*")) {
            query.whereIn("capability", cast capabilities);
        }
        var owner = InstalledPackage.query.selectCount()
            .whereColumn("cms_packages.id", "content_types.owner")
            .where("enabled", 1)
            .where("restart_required", 0);
        var items = ContentItem.query.selectCount()
            .whereColumn("content_items.content_type", "content_types.key")
            .where("status", "!=", "trash");
        if (author > 0) {
            items.where("author_id", author);
        }
        query.selectSub(owner, "owner_active").selectSub(items, "items");
        if (search != "") {
            var prefix = CategoryData.key(search);
            var escaped = StringTools.replace(StringTools.replace(StringTools.replace(prefix, "!",
                "!!"), "%", "!%"), "_", "!_");
            var pattern = '%${escaped}%';
            query.where(matches -> matches.whereLike("name", pattern).orWhereLike("key", pattern));
        }
        return query;
    }

    public static function page(search:String, cursor:Null<PageCursor>, author:Int = 0,
            capabilities:Array<String> = null):QueryPage<ContentTypeSummary> {
        return ContentCache.remember("structure", "manage", [
            search,
            Pagination.token(cursor),
            PAGE_SIZE,
            author,
            capabilities,
            ContentCache.revision("items"),
            packageRevision()
        ], () -> {
            var query = filtered(search, author, capabilities);
            if (cursor != null) {
                query.where("key", cursor.before ? "<" : ">", cursor.id);
            }
            var direction = cursor != null && cursor.before ? "DESC" : "ASC";
            var rows:Array<ContentTypeSummary> = query.orderBy("key", direction)
                .limit(PAGE_SIZE + 1)
                .get()
                .map(model -> cast model.toObject());
            return Pagination.slice(rows, PAGE_SIZE, cursor);
        });
    }

    public static function count(search:String, capabilities:Array<String> = null):Int {
        return ContentCache.remember("structure", "count", [search, capabilities],
            () -> filtered(search, 0, capabilities).count());
    }

    public static function dashboard(author:Int,
            capabilities:Array<String>):Array<ContentTypeSummary> {
        return ContentCache.remember("structure", "dashboard-collections",
            [author, capabilities, revision(), ContentCache.revision("items"), 12], () -> {
                return available(filtered("", author,
                    capabilities)).orderBy("position")
                    .orderBy("key")
                    .limit(12)
                    .get()
                    .map(model -> cast model.toObject());
            });
    }

    public static function dashboardCount(capabilities:Array<String>):Int {
        return ContentCache.remember("structure", "dashboard-collection-count",
            [capabilities, revision()], () -> {
                return accessible(ContentType.query.select(["key"]), capabilities).count();
            });
    }

    static function text(input:Dynamic, key:String, maximum:Int, fallback:String = ""):String {
        var value:Dynamic = Reflect.field(input, key);
        if (value == null) {
            return fallback;
        }
        if (!(value is String) || StringTools.trim(value).length > maximum) {
            throw new Exception('Invalid content type field: ${key}');
        }
        return StringTools.trim(value);
    }

    static function flag(input:Dynamic, key:String, fallback:Bool):Bool {
        var value:Dynamic = Reflect.field(input, key);
        if (value == null) {
            return fallback;
        }
        if (!Std.isOfType(value, Bool)) {
            throw new Exception("Content type flags must be boolean values.");
        }
        return value == true;
    }

    static function integer(input:Dynamic, key:String, maximum:Int, fallback:Int):Int {
        var value:Dynamic = Reflect.field(input, key);
        if (value == null) {
            return fallback;
        }
        if (!Std.isOfType(value, Int) || value < (key == "minimumTitleLength" ? 1 : 0)
            || value > maximum) {
            throw new Exception("Enter a valid content length constraint.");
        }
        return value;
    }

    public static function validateFields(input:Dynamic):Array<ContentFieldDefinition> {
        if (input == null) {
            return [];
        }
        if (!(input is Array)) {
            throw new Exception("Content fields must be a list.");
        }
        var source:Array<Dynamic> = input;
        if (source.length > MAX_FIELDS) {
            throw new Exception("A content type can define up to 32 custom fields.");
        }
        var result:Array<ContentFieldDefinition> = [];
        var used:Map<String, Bool> = [];
        for (entry in source) {
            var key = text(entry, "key", 32);
            var label = text(entry, "label", 100);
            var kind = text(entry, "kind", 20, "text");
            if (!validKey(key) || label == "" || used.exists(key) || !fieldKinds.contains(kind)) {
                throw new Exception("Choose unique custom field keys, labels and supported field types.");
            }
            used.set(key, true);
            var options:Array<{value:String, label:String}> = [];
            var choices:Dynamic = Reflect.field(entry, "options");
            if (choices != null && !(choices is Array)) {
                throw new Exception("Field choices must be a list.");
            }
            var supplied:Array<Dynamic> = choices ?? [];
            if (supplied.length > 50) {
                throw new Exception("A choice field can contain up to 50 options.");
            }
            var optionKeys:Map<String, Bool> = [];
            for (choice in supplied) {
                var value = text(choice, "value", 120);
                var name = text(choice, "label", 120);
                if (value == "" || name == "" || optionKeys.exists(value)) {
                    throw new Exception("Choice values must be unique and have labels.");
                }
                optionKeys.set(value, true);
                options.push({value: value, label: name});
            }
            if (kind == "select" && options.length == 0) {
                throw new Exception("Add choices to a select field.");
            }
            var publicVisible = flag(entry, "publicVisible", true);
            var filterable = flag(entry, "filterable", false);
            var inList = flag(entry, "inList", false);
            if (filterable && (!publicVisible || ["textarea", "image"].contains(kind))) {
                throw new Exception("Only public scalar fields can be used as collection filters.");
            }
            if (inList && ["textarea", "image"].contains(kind)) {
                throw new Exception("List columns support short text, numbers, dates, choices and booleans.");
            }
            result.push({
                key: key,
                label: label,
                kind: kind,
                required: flag(entry, "required", false),
                publicVisible: publicVisible,
                filterable: filterable,
                inList: inList,
                help: text(entry, "help", 300),
                options: options
            });
        }
        var listed = 0;
        for (field in result) {
            if (field.inList) {
                listed++;
            }
        }
        if (listed > 6) {
            throw new Exception("Choose up to six custom fields for list columns.");
        }
        return result;
    }

    public static function save(input:Dynamic, owner:String = "", creating:Bool = false):String {
        if (input == null || !Reflect.isObject(input) || (input is Array)) {
            throw new Exception("Provide a content type definition.");
        }
        var key = text(input, "key", 32);
        if (!validKey(key)) {
            throw new Exception("Use a stable lowercase content type key, with letters, numbers or underscores.");
        }
        return ContentLocks.run('type-${key}', () -> saveLocked(input, key, owner, creating));
    }

    static function saveLocked(input:Dynamic, key:String, owner:String, creating:Bool):String {
        var existing = ContentType.query.where("key", key).limit(1).first();
        if ((creating && existing != null) || (existing != null && existing.owner != owner)) {
            throw new Exception("This content type key belongs to another definition.");
        }
        var name = text(input, "name", 100);
        var singular = text(input, "singular", 80);
        var path = text(input, "publicPath", 60, StringTools.replace(key, "_", "-"));
        var icon = text(input, "icon", 40, "file");
        if (name == ""
            || singular == ""
            || !Slug.valid(path)
            || reservedPaths.contains(path)
            || !~/^[a-z][a-z0-9-]*(?![\s\S])/.match(icon)) {
            throw new Exception("Enter collection labels and a public path that is not reserved by the CMS.");
        }
        if (ContentType.query.where("public_path", path).where("key", "!=", key).exists()) {
            throw new Exception("Another content type already uses this public path.");
        }
        if (ContentTypePath.query.where("path", path).where("type_key", "!=", key).exists()) {
            throw new Exception("This public path is retained as a redirect for another collection.");
        }
        var template = text(input, "template", 80, "ContentDetail");
        var archiveTemplate = text(input, "archiveTemplate", 80, "ContentIndex");
        if (["Home", "ContentIndex", "About", "NotFound"].contains(template)
            || ["Home", "ContentDetail", "Page", "About", "NotFound"].contains(archiveTemplate)) {
            throw new Exception("Choose a template for the matching detail or archive view.");
        }
        for (name in [template, archiveTemplate]) {
            if (!~/^[A-Za-z][A-Za-z0-9_-]{0,79}(?![\s\S])/.match(name)) {
                throw new Exception("Use a public theme template name without path separators.");
            }
        }
        var requested:Dynamic = Reflect.field(input, "features");
        if (!(requested is Array)) {
            throw new Exception("Choose the editor features for this collection.");
        }
        var source:Array<Dynamic> = requested;
        var features:Array<String> = [];
        for (value in source) {
            if (!(value is String) || !supportedFeatures.contains(value)) {
                throw new Exception("This content type requests an unsupported editor feature.");
            }
            if (!features.contains(value)) {
                features.push(value);
            }
        }
        var fields = validateFields(Reflect.field(input, "fields"));
        var encodedFields = Json.stringify(fields);
        if (encodedFields.length > 48000) {
            throw new Exception("The custom field definition exceeds its storage limit.");
        }
        var labelsInput:Dynamic = Reflect.field(input, "labels") ?? {};
        var labels:Dynamic = {};
        for (label in ["create", "edit", "save", "title", "description"]) {
            Reflect.setField(labels, label, text(labelsInput, label, 300));
        }
        var enabled = flag(input, "enabled", true);
        var dedicated = flag(input,
            "dedicatedAccess", existing != null && existing.capability != "content");
        var capability = dedicated ? 'content.${key}' : "content";
        if (dedicated) {
            Roles.ensureCapability(capability, ('${name} access').substr(0, 120), "Collections",
                owner);
        }
        if (existing != null && existing.system == 1 && !enabled) {
            throw new Exception("The built-in content collections must remain enabled.");
        }
        var values:Map<String, Dynamic> = [
            "key" => key,
            "name" => name,
            "singular" => singular,
            "description" => text(input, "description", 500),
            "icon" => icon,
            "admin_path" => existing == null ? 'collections/${key}' : existing.admin_path,
            "public_path" => path,
            "public_visible" => flag(input, "publicVisible", true) ? 1 : 0,
            "has_archive" => flag(input, "hasArchive", true) ? 1 : 0,
            "enabled" => enabled ? 1 : 0,
            "system" => existing == null ? 0 : existing.system,
            "owner" => owner,
            "capability" => capability,
            "position" => integer(input, "position", 500,
                existing == null ? 10 : existing.position),
            "template" => template,
            "archive_template" => archiveTemplate,
            "features" => Json.stringify(features),
            "fields" => encodedFields,
            "labels" => Json.stringify(labels),
            "minimum_title_length" => integer(input, "minimumTitleLength", 180, 1),
            "minimum_content_length" => integer(input, "minimumContentLength", 100000, 0),
            "minimum_excerpt_length" => integer(input, "minimumExcerptLength", 500, 0),
            "updated_at" => SiteSettingsStore.timestamp()
        ];
        DBStatic.transaction(() -> {
            if (existing == null) {
                values.set("created_at", SiteSettingsStore.timestamp());
                ContentType.query.insert(values);
            } else {
                if (existing.public_path != path) {
                    ContentTypePath.query.upsert(["path" => existing.public_path, "type_key" => key],
                        ["path"],
                        ["type_key"]);
                }
                existing.update(values);
            }
        });
        ContentCache.changed("structure");
        ContentCache.contentChanged();
        return key;
    }

    /** Native modules call this during creation; existing site customizations are retained. */
    public static function register(pluginSlug:String, input:Dynamic):String {
        var owner = 'plugin-${pluginSlug}';
        if (!InstalledPackage.query.where("id", owner).where("kind", "plugin").exists()) {
            throw new Exception("Install the owning plugin before registering its content type.");
        }
        var key = text(input, "key", 32);
        var existing = record(key, false);
        if (existing != null) {
            if (existing.owner != owner) {
                throw new Exception("This content type belongs to another owner.");
            }
            return key;
        }
        return save(input, owner, true);
    }

    public static function remove(key:String):Void {
        ContentLocks.run('type-${key}', () -> {
            removeLocked(key);
            return true;
        });
    }

    static function removeLocked(key:String):Void {
        var type = record(key, false);
        if (type == null || type.system == 1 || type.owner != "") {
            throw new Exception("Only site-owned custom content types can be removed.");
        }
        if (ContentItem.query.where("content_type", key).exists()
            || EditorDraft.query.where("kind", key)
                .where("expires_epoch", ">", Date.now().getTime())
                .exists()) {
            throw new Exception("This collection still contains content. Disable it to keep the data.");
        }
        DBStatic.transaction(() -> {
            ContentTypePath.query.where("type_key", key).delete();
            ContentType.query.where("key", key).delete();
        });
        ContentCache.changed("structure");
    }
}
