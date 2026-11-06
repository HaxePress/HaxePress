package hx.press.backup;

#if jvm
import haxe.Exception;
import haxe.Json;
import haxe.io.Bytes;
import hx.press.backup.BackupTable.BackupTableDefinition;
import hx.press.backup.SiteBackupArchive.BackupSelection;
import hx.press.backup.SiteBackupArchive.ExtractedBackup;
import hx.press.media.MediaReferences;
import hx.press.packages.BuiltInTheme;
import hx.press.packages.PackageArchiveInput.ArchiveSource;
import hx.press.packages.PackageManifest;
import hx.press.packages.PackageStorage;
import hx.press.packages.SafePackageArchive;
import hx.press.themes.ThemeAssets;
import hx.well.database.Connection;
import hx.well.database.query.QueryBuilder;
import hx.well.database.schema.SchemaBuilder;
import hx.well.database.schema.SchemaGrammar;
import hx.well.facades.Schema;
import hx.well.model.BaseModel;
import hx.well.storage.StorageDisk;

class SiteBackupDatabase {
    static inline var CONNECTION = "haxepress-backup";
    public static inline var RESTORED = "restored.sqlite";
    static final TRANSIENT = [
        "login_attempts",
        "package_uploads",
        "image_uploads",
        "theme_ai_connections",
        "scheduled_backup_files"
    ];
    static final CONTENT = [
        "content_revisions",
        "content_tags",
        "content_values",
        "editor_drafts",
        "content_items",
        "content_type_paths",
        "categories",
        "tags"
    ];
    static final THEMES = ["theme_ai_permissions", "theme_assets", "theme_designs"];
    static final CONTENT_REFERENCES = [
        "content_revisions" => "document_id",
        "editor_drafts" => "document_id",
        "content_tags" => "content_id",
        "content_values" => "content_id",
        "menu_links" => "content_id"
    ];
    static final CORE = [
        "admins",
        "settings",
        "content_types",
        "cms_packages",
        "package_hooks",
        "scheduled_jobs",
        "media_assets",
        "media_dependencies",
        "media_dependency_sources",
        "navigation_regions",
        "menu_links",
        "activity_logs",
        "roles",
        "role_grants",
        "capabilities"
    ];

    public static function exportData(target:StorageDisk, assets:StorageDisk,
            sections:BackupSelection):Array<ArchiveSource> {
        var schema = Schema.connection("default");
        var connection = Connection.get();
        var files:Array<ArchiveSource>;
        schema.startReadSnapshot();
        try {
            files = exportTables(target, sections);
            for (path in managedFiles(assets, sections, "default", false)) {
                files.push(SiteBackupArchive.file(assets, path, path));
            }
        } catch (error:Dynamic) {
            connection.rollback();
            throw error;
        }
        connection.rollback();
        return files;
    }

    static function exportTables(target:StorageDisk,
            sections:BackupSelection):Array<ArchiveSource> {
        var schema = Schema.connection("default");
        schema.requirePortableTables();
        var required = requiredTables();
        var names = schema.getTableListing()
            .filter(name -> sections.plugins || required.contains(name));
        names.sort(Reflect.compare);
        requireCore(names);
        if (names.length > BackupTable.MAX_TABLES) {
            throw new Exception("The backup contains too many database tables.");
        }
        var sqlite = Connection.driver() == "sqlite";
        var definitions = names.map(name -> BackupTable.read(schema, name, sqlite));
        var files:Array<ArchiveSource> = [];
        var omitted = omittedTables(sections, names);
        var remaining = SiteBackupArchive.MAX_EXPANDED;
        for (table in definitions) {
            var text = sqlite ? table.columns.filter(column -> column.kind == "varchar") : [];
            var transform = (row:Dynamic) -> {
                exportValues(table.name, row, sections);
                for (column in text) {
                    var value:Dynamic = Reflect.field(row, column.name);
                    if (value is String) {
                        var length = (value : String).length;
                        if (length > column.size) {
                            column.size = length;
                        }
                    }
                }
            };
            if (table.name == "content_items") {
                if (sections.content) {
                    var items = new BackupRows(table, () -> selectedContent(sections), transform,
                        true);
                    var content = BackupContent.write(target, items.next);
                    files = files.concat(content);
                    for (file in content) {
                        remaining -= file.size;
                    }
                }
                continue;
            }
            var path = BackupRows.path(table.name);
            if (omitted.contains(table.name)
                || (!sections.content && table.name == "activity_logs")) {
                target.put(path, Bytes.alloc(0), "private");
            } else {
                var rows = new BackupRows(table, () -> exportQuery(table.name, sections),
                    transform);
                var stream = new BackupInput(rows, remaining);
                try {
                    target.writeStream(path, stream, "private");
                } catch (failure:Dynamic) {
                    stream.close();
                    throw failure;
                }
                stream.close();
                remaining -= stream.count;
            }
            files.push(SiteBackupArchive.file(target, path, path));
        }
        var encoded = Bytes.ofString(Json.stringify(definitions));
        if (encoded.length > SiteBackupArchive.MAX_SCHEMA || encoded.length > remaining) {
            throw new Exception("The backup table definitions exceed the size limit.");
        }
        var schemaPath = SiteBackupArchive.SCHEMA;
        target.put(schemaPath, encoded, "private");
        files.push(SiteBackupArchive.file(target, schemaPath, schemaPath));
        return files;
    }

    static function exportQuery(table:String, sections:BackupSelection):QueryBuilder<Dynamic> {
        var rows = query(table, "default");
        switch (table) {
            case "cms_packages":
                selectPackages(rows, sections);
            case "package_hooks":
                var packages = selectPackages(query("cms_packages", "default"), sections);
                rows.whereInQuery("package_id", packages.select(["id"]));
            case "scheduled_jobs":
                if (!sections.plugins) {
                    rows.whereLike("id", "core:%");
                }
            case "settings":
                rows.where("key", "NOT LIKE", "cms_builtin_%");
            case "content_types":
                if (!sections.content) {
                    rows.where(group -> group.where("system", 1).orWhere("owner", "!=", ""));
                }
                if (!sections.plugins) {
                    rows.where("owner", "NOT LIKE", "plugin-%");
                }
            case "content_type_paths":
                if (!sections.plugins) {
                    rows.whereInQuery("type_key", coreTypes());
                }
            case "content_revisions", "content_tags", "content_values":
                if (!sections.plugins) {
                    var column = CONTENT_REFERENCES.get(table);
                    rows.whereInQuery(column, selectedContent(sections).select(["id"]));
                }
            case "editor_drafts":
                if (!sections.plugins) {
                    rows.where(group -> {
                        group.whereInQuery("document_id", selectedContent(sections).select(["id"]));
                        group.orWhere(draft -> draft.where("document_id", 0)
                            .whereInQuery("kind", coreTypes()));
                    });
                }
            case "menu_links":
                if (!sections.content) {
                    rows.where("content_id", 0).where("collection_key", "");
                } else if (!sections.plugins) {
                    rows.where(group -> group.whereInQuery("content_id",
                        selectedContent(sections).select(["id"]))
                        .orWhere("content_id", 0));
                    rows.where(group -> group.whereInQuery("collection_key", coreTypes())
                        .orWhere("collection_key", ""));
                }
            case "media_dependencies", "media_dependency_sources":
                if (!sections.themes) {
                    rows.where("owner", "NOT LIKE", "theme-%");
                }
                if (!sections.plugins) {
                    rows.where("owner", "NOT LIKE", "plugin-%");
                }
            case "activity_logs":
                if (!sections.themes) {
                    rows.where("entity", "!=", "theme");
                }
                if (!sections.plugins) {
                    rows.where("entity", "!=", "plugin");
                }
            case _:
        }
        return rows;
    }

    static function coreTypes():QueryBuilder<Dynamic> {
        return query("content_types",
            "default").select(["key"]).where("owner", "NOT LIKE", "plugin-%");
    }

    static function selectedContent(sections:BackupSelection):QueryBuilder<Dynamic> {
        var rows = query("content_items", "default");
        return sections.plugins ? rows : rows.whereInQuery("content_type", coreTypes());
    }

    static function selectPackages(rows:QueryBuilder<Dynamic>,
            sections:BackupSelection):QueryBuilder<Dynamic> {
        if (!sections.themes) {
            rows.where(group -> group.where("kind", "!=", "theme").orWhere("id", BuiltInTheme.ID));
        }
        if (!sections.plugins) {
            rows.where("kind", "!=", "plugin");
        }
        return rows;
    }

    static function exportValues(table:String, row:Dynamic, sections:BackupSelection):Void {
        if (table == "scheduled_jobs") {
            row.lease_until = 0;
            row.run_token = "";
            row.last_error = "";
        }
        if (table == "settings") {
            switch (row.key) {
                case "home_mode" if (!sections.content):
                    row.value = "collection";
                case "home_page" if (!sections.content):
                    row.value = "0";
                case "home_type" if (!sections.content):
                    row.value = "entry";
                case "home_template" if (!sections.themes):
                    row.value = "Home";
                case _:
            }
        }
        if (table == "cms_packages" && !sections.themes && row.id == BuiltInTheme.ID) {
            row.enabled = "1";
            row.settings = "{}";
        }
    }

    static function omittedTables(sections:BackupSelection, tables:Array<String>):Array<String> {
        var omitted = TRANSIENT.copy();
        if (!sections.content) {
            omitted = omitted.concat(CONTENT);
        }
        if (!sections.themes) {
            omitted = omitted.concat(THEMES);
        }
        if (!sections.plugins) {
            var pluginTables = tables.filter(table -> StringTools.startsWith(table, "plugin_")
                || table == "subscribers");
            omitted = omitted.concat(pluginTables);
        }
        return omitted;
    }

    static function requiredTables():Array<String> {
        return CORE.concat(CONTENT).concat(THEMES).concat(TRANSIENT);
    }

    static function requireCore(names:Array<String>):Void {
        for (table in requiredTables()) {
            if (!names.contains(table)) {
                throw new Exception('The backup database is missing the ${table} table.');
            }
        }
    }

    static function managedFiles(storage:StorageDisk, sections:BackupSelection, connection:String,
            validatePackages:Bool):Array<String> {
        var files:Array<String> = [];
        var media = query("media_assets",
            connection).select(["filename"])
            .limit(SiteBackupArchive.MAX_MANAGED_FILES + 1)
            .getResultSet();
        while (media.hasNext()) {
            var filename:String = media.next().filename;
            if (!MediaReferences.validFilename(filename)) {
                throw new Exception("The backup contains an invalid media filename.");
            }
            includeFile(storage, files, 'media/${filename}');
        }
        if (sections.themes) {
            var images = query("theme_assets",
                connection).select(["theme_id", "filename"])
                .limit(SiteBackupArchive.MAX_MANAGED_FILES + 1)
                .getResultSet();
            while (images.hasNext()) {
                var image = images.next();
                if (!ThemeAssets.validThemeId(image.theme_id)
                    || !ThemeAssets.validFilename(image.filename)) {
                    throw new Exception("The backup contains an invalid theme image filename.");
                }
                includeFile(storage, files, 'themes/${image.theme_id}/${image.filename}');
            }
        }
        var packages = query("cms_packages", connection);
        if (!validatePackages) {
            selectPackages(packages, sections);
        }
        var records = packages.select(["id", "kind", "plugin_id", "directory", "manifest"])
            .limit(SiteBackupArchive.MAX_MANAGED_FILES + 1)
            .getResultSet();
        while (records.hasNext()) {
            var record = records.next();
            if (record.id == BuiltInTheme.ID) {
                continue;
            }
            if ((record.kind == "theme" && !sections.themes)
                || (record.kind == "plugin" && !sections.plugins)) {
                throw new Exception("The database contains a package outside the selected sections.");
            }
            var manifest = PackageManifest.parse(record.manifest);
            if (manifest.kind != record.kind
                || '${manifest.kind}-${manifest.slug}' != record.id
                || manifest.pluginId != record.plugin_id) {
                throw new Exception("An installed package has invalid metadata.");
            }
            if (manifest.layout == "builder") {
                if (!query("theme_designs", connection).where("id", record.id).exists()) {
                    throw new Exception("A visual theme is missing its design.");
                }
                continue;
            }
            var directory = 'extensions/${PackageStorage.installed(record.directory)}';
            if (!storage.fileExists('${directory}/${PackageManifest.FILENAME}')) {
                throw new Exception("An installed package is missing its files.");
            }
            if (validatePackages) {
                var inspected = SafePackageArchive.inspect(storage, directory).manifest;
                if (inspected.slug != manifest.slug
                    || inspected.kind != manifest.kind
                    || inspected.version != manifest.version
                    || inspected.pluginId != manifest.pluginId) {
                    throw new Exception("An installed package does not match its files.");
                }
            }
            for (path in storage.allFiles(directory)) {
                includeFile(storage, files, path);
            }
        }
        files.sort(Reflect.compare);
        return files;
    }

    static function includeFile(storage:StorageDisk, files:Array<String>, path:String):Void {
        if (files.length >= SiteBackupArchive.MAX_MANAGED_FILES) {
            throw new Exception("The backup contains too many files.");
        }
        if (!storage.fileExists(path)) {
            throw new Exception("A file referenced by the backup is missing.");
        }
        files.push(path);
    }

    public static function replay(storage:StorageDisk, backup:ExtractedBackup, config:Dynamic,
            rollback:Bool, skipDamaged:Bool, ?publish:Void->Void):Array<Int> {
        var definitions = readDefinitions(storage, backup.manifest.sections);
        var names = definitions.map(table -> table.name);
        var mysql = config.path == null;
        requireReferences(definitions, mysql);
        var created:Array<String> = [];
        var published = false;
        try {
            return Connection.withConfiguration(CONNECTION, config, () -> {
                var schema = Schema.connection(CONNECTION);
                if (schema.getTableListing().length != 0) {
                    throw new Exception("Choose an empty database. Existing data will not be overwritten.");
                }
                schema.prepareLogicalRestore();
                for (table in definitions) {
                    BackupTable.create(schema, table, mysql, () -> created.push(table.name));
                }
                if (mysql) {
                    for (table in definitions) {
                        if (table.foreign.length > 0) {
                            schema.table(table.name,
                                blueprint -> BackupTable.addForeign(blueprint, table.foreign));
                        }
                    }
                }
                var skipped = loadRows(storage, backup, schema, definitions, names, rollback,
                    skipDamaged, !mysql);
                if (publish != null) {
                    publish();
                    published = true;
                }
                return skipped;
            });
        } catch (failure:Dynamic) {
            if (!rollback && !published && created.length > 0) {
                try {
                    created.reverse();
                    Connection.withConfiguration(CONNECTION, config, () -> {
                        var schema = Schema.connection(CONNECTION);
                        schema.withoutForeignKeyConstraints(() -> {
                            for (name in created) {
                                schema.dropIfExists(name);
                            }
                        });
                        return true;
                    });
                } catch (_:Dynamic) {
                    throw new Exception("Restore failed and its new tables could not all be removed. Check the target database before retrying.");
                }
            }
            throw failure;
        }
    }

    static function loadRows(storage:StorageDisk, backup:ExtractedBackup, schema:SchemaBuilder,
            tables:Array<BackupTableDefinition>, names:Array<String>, rollback:Bool,
            skipDamaged:Bool, sqlite:Bool):Array<Int> {
        var skipped:Array<Int> = [];
        schema.withoutForeignKeyConstraints(() -> {
            var connection = Connection.get(CONNECTION);
            connection.startTransaction();
            try {
                for (table in tables) {
                    if (table.name != "content_items") {
                        BackupRows.importTable(storage, table, () -> query(table.name), sqlite);
                    }
                }
                verifySite(storage, backup, names);
                skipped = restoreContent(storage, backup, skipDamaged);
                schema.validateForeignKeys(names);
                if (rollback) {
                    connection.rollback();
                } else {
                    connection.commit();
                }
            } catch (failure:Dynamic) {
                connection.rollback();
                throw failure;
            }
        });
        return skipped;
    }

    static function readDefinitions(storage:StorageDisk,
            sections:BackupSelection):Array<BackupTableDefinition> {
        var data:Dynamic = Json.parse(storage.get(SiteBackupArchive.SCHEMA));
        if (!(data is Array) || data.length > BackupTable.MAX_TABLES) {
            throw new Exception("The backup table list is invalid.");
        }
        var definitions:Array<BackupTableDefinition> = cast data;
        var names:Array<String> = [];
        var seen:Map<String, Bool> = [];
        var expected = [SiteBackupArchive.SCHEMA];
        var required = requiredTables();
        for (table in definitions) {
            BackupTable.validate(table);
            var key = SchemaGrammar.asciiLower(table.name);
            if (seen.exists(key) || (!sections.plugins && !required.contains(table.name))) {
                throw new Exception("The backup contains an unexpected table.");
            }
            seen.set(key, true);
            names.push(table.name);
            if (table.name != "content_items") {
                expected.push(BackupRows.path(table.name));
            }
        }
        requireCore(names);
        var received = storage.files("database");
        received.sort(Reflect.compare);
        expected.sort(Reflect.compare);
        if (received.join("\n") != expected.join("\n")) {
            throw new Exception("The database row files do not match their table definitions.");
        }
        return definitions;
    }

    static function requireReferences(tables:Array<BackupTableDefinition>, mysql:Bool):Void {
        var byName = [for (table in tables) table.name => table];
        for (table in tables) {
            for (foreign in table.foreign) {
                var parent = byName.get(foreign.foreignTable);
                if (parent == null) {
                    throw new Exception('Table ${table.name} references a table outside the backup.');
                }
                BackupTable.requireColumns(foreign.foreignColumns,
                    parent.columns.map(column -> column.name));
                if (mysql) {
                    for (index in 0...foreign.columns.length) {
                        var child = table.columns.filter(column ->
                            column.name == foreign.columns[index])[0];
                        var target = parent.columns.filter(column ->
                            column.name == foreign.foreignColumns[index])[0];
                        if (BackupTable.integer(child.kind) && BackupTable.integer(target.kind)) {
                            child.kind = target.kind;
                            child.unsigned = target.unsigned;
                        }
                    }
                }
            }
        }
    }

    static function verifySite(storage:StorageDisk, backup:ExtractedBackup,
            tables:Array<String>):Void {
        var sections = backup.manifest.sections;
        if (!sections.plugins && query("scheduled_jobs").where("id", "NOT LIKE", "core:%")
            .exists()) {
            throw new Exception("The backup contains schedules outside its selected sections.");
        }
        for (table in omittedTables(sections, tables)) {
            if (query(table).exists()) {
                throw new Exception('The backup contains data outside its selected sections in ${table}.');
            }
        }
        if (!query("admins").where("active", 1).where("role", "owner").exists()) {
            throw new Exception("The backup must contain an active owner account.");
        }
        var expected = managedFiles(storage, sections, CONNECTION, true);
        var received = backup.files.copy();
        received.sort(Reflect.compare);
        if (received.join("\n") != expected.join("\n")) {
            throw new Exception("The backup files do not match its selected sections.");
        }
    }

    static function restoreContent(storage:StorageDisk, backup:ExtractedBackup,
            skipDamaged:Bool):Array<Int> {
        if (query("content_items").exists()) {
            throw new Exception("The backup database contains unexpected content rows.");
        }
        var skipped:Array<Int> = [];
        if (backup.manifest.sections.content) {
            var ids = BackupContent.ids(storage, backup.contentIds);
            var columns = Schema.connection(CONNECTION).getWritableColumnListing("content_items");
            for (id in ids) {
                var record = BackupContent.read(storage, id, columns);
                if (record != null) {
                    query("content_items").insert(record);
                } else if (skipDamaged) {
                    skipped.push(id);
                } else {
                    throw new Exception('Content item ${id} is damaged or missing.');
                }
            }
        }
        if (!backup.intact && skipped.length == 0) {
            throw new Exception("The backup MD5 checksum does not match.");
        }
        var offset = 0;
        while (offset < skipped.length) {
            var batch = skipped.slice(offset, offset + 200);
            for (table => column in CONTENT_REFERENCES) {
                query(table).whereIn(column, cast batch).delete();
            }
            var homeIds = batch.map(id -> Std.string(id));
            var home = query("settings").where("key", "home_page").whereIn("value", cast homeIds);
            if (home.exists()) {
                home.update(["value" => "0"]);
                query("settings").where("key", "home_mode").update(["value" => "collection"]);
            }
            offset += batch.length;
        }
        return skipped;
    }

    static function query(table:String, connection:String = CONNECTION):QueryBuilder<Dynamic> {
        var model = new BaseModel<Dynamic>();
        model.setConnection(connection);
        model.setTable(table);
        return new QueryBuilder(model);
    }
}
#end
