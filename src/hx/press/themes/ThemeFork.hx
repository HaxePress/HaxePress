package hx.press.themes;

import haxe.Exception;
import haxe.Json;
import haxe.crypto.Md5;
import hx.press.Activity;
import hx.press.CategoryData;
import hx.press.ContentCache;
import hx.press.SiteSettingsStore;
import hx.press.media.MediaDependencies;
import hx.press.model.InstalledPackage;
import hx.press.model.ThemeAsset;
import hx.press.model.ThemeDesign;
import hx.press.packages.BuiltInTheme;
import hx.press.packages.PackageArchiveInput;
import hx.press.packages.PackageArchiveInput.ArchiveSource;
import hx.press.packages.PackageManager;
import hx.press.packages.PackageManifest;
import hx.press.packages.PackageSettings;
import hx.press.packages.PackageStorage;
import hx.press.packages.SafePackageArchive;
import hx.press.storage.TemporaryDownloadInput;
import hx.press.view.ViewSources;
import hx.well.facades.DBStatic;
import hx.well.facades.Storage;
import hx.well.http.InputResponse;
import hx.well.internal.SecureToken;
import hx.well.storage.StorageDisk;

/**
    Copies a theme into a new theme that belongs to the site. Updates leave
    a fork alone, so forking is how a bundled theme is changed. A visual
    design is copied with its draft, its published version and its images;
    a packaged theme with its files; the built-in theme with the
    application templates it renders, as a packaged theme.
**/
class ThemeFork {
    /** The application templates the built-in theme renders its pages with. **/
    static final builtInViews = [
        "Home",
        "ContentIndex",
        "ContentDetail",
        "Page",
        "About",
        "NotFound",
        "SiteLayout",
        "ContentCard"
    ];

    /** Forks a theme and returns the ID of the copy. **/
    public static function fork(id:String, name:String, userId:Int, userName:String):String {
        var source = InstalledPackage.query.select(["id", "slug", "directory", "manifest", "settings"])
            .where("id", id)
            .where("kind", "theme")
            .limit(1)
            .first();
        if (source == null) {
            throw new Exception("This theme is no longer available.");
        }
        if (ThemeDesign.query.where("id", id).exists()) {
            return design(source.id, source.manifest, name, userId, userName);
        }
        return packaged(source, name, userId, userName);
    }

    /** Whether a theme's files can be downloaded: packaged themes other than the built-in one. **/
    public static function downloadable(id:String, designed:Bool):Bool {
        return !designed && !BuiltInTheme.isBuiltIn(id);
    }

    /** The installed files of a packaged theme as a ZIP that installs as the same theme. **/
    public static function download(id:String):InputResponse {
        var item = InstalledPackage.query.select(["slug", "version", "directory"])
            .where("id", id)
            .where("kind", "theme")
            .limit(1)
            .first();
        if (item == null || !downloadable(id, ThemeDesign.query.where("id", id).exists())) {
            throw new Exception("Choose a packaged theme to download.");
        }
        var extensions = Storage.disk("extensions");
        var folder = PackageStorage.installed(item.directory);
        var files:Array<ArchiveSource> = [
            for (file in extensions.files(folder, true))
                {
                    name: file.substr(folder.length + 1),
                    size: extensions.size(file),
                    open: () -> extensions.readStream(file)
                }
        ];
        var exports = Storage.disk("exports");
        var path = '${SecureToken.generate(32)}.zip';
        try {
            var archive = new PackageArchiveInput(files);
            try {
                exports.writeStream(path, archive);
                archive.close();
            } catch (error:Dynamic) {
                archive.close();
                throw error;
            }
            var response = exports.download(path, '${item.slug}-${item.version}.zip',
                ["Content-Type" => "application/zip", "Cache-Control" => "private, no-store"]);
            response.input = new TemporaryDownloadInput(response.input, () -> exports.delete(path));
            return response;
        } catch (error:Dynamic) {
            if (exports.fileExists(path)) {
                exports.delete(path);
            }
            throw error;
        }
    }

    /** A new slug for a copy of `slug`, within the manifest's 64 characters. **/
    static function slugFor(slug:String):String {
        var suffix = Md5.encode(SecureToken.generate(32)).substr(0, 8);
        var base = slug.substr(0, 64 - suffix.length - 6);
        while (StringTools.endsWith(base, "-")) {
            base = base.substr(0, base.length - 1);
        }
        return '${base}-copy-${suffix}';
    }

    /**
        Stages a copy of a packaged theme, or of the built-in theme, and
        installs it through the regular package checks, so the copy is
        inspected like an upload. Its settings are copied after installation.
    **/
    static function packaged(source:InstalledPackage, name:String, userId:Int,
            userName:String):String {
        var manifest:Dynamic = Json.parse(source.manifest);
        manifest.slug = slugFor(source.slug);
        manifest.name = name;
        manifest.author = userName;
        var builtIn = BuiltInTheme.isBuiltIn(source.id);
        var inspection:Dynamic = PackageManager.stageArchive("theme", userId, destination -> {
            var disk = Storage.disk("extensions");
            if (builtIn) {
                writeBuiltIn(disk, destination, manifest);
            } else {
                copyFolder(disk, PackageStorage.installed(source.directory), destination);
            }
            disk.put('${destination}/${PackageManifest.FILENAME}',
                Json.stringify(manifest, null, "  "));
            return SafePackageArchive.inspect(disk, destination);
        });
        var key:String = inspection.key;
        var id = try {
            PackageManager.install(key, "theme", userId, userName, false);
        } catch (error:Dynamic) {
            PackageManager.discard(key, userId);
            throw error;
        }
        var settings = PackageSettings.stored(source.settings);
        if (settings.keys().hasNext()) {
            PackageManager.configure(id, settings, [], userId, userName);
        }
        return id;
    }

    static function copyFolder(disk:StorageDisk, folder:String, destination:String):Void {
        // Installed package trees contain at most SafePackageArchive.MAX_FILES entries.
        for (file in disk.files(folder, true)) {
            disk.copy(file, '${destination}/${file.substr(folder.length + 1)}');
        }
    }

    /** The built-in theme's pages and translations, as the views of a packaged theme. **/
    static function writeBuiltIn(disk:StorageDisk, destination:String, manifest:Dynamic):Void {
        for (name in builtInViews) {
            var template = ViewSources.source(name);
            if (template == null) {
                throw new Exception('The application template ${name} is missing.');
            }
            disk.put('${destination}/views/${name}.well.html', template);
        }
        var translations:Dynamic = manifest.translations == null ? {} : manifest.translations;
        for (locale in Reflect.fields(translations)) {
            var catalogue = BuiltInTheme.translations(locale);
            if (catalogue == null) {
                Reflect.deleteField(translations, locale);
                continue;
            }
            disk.put('${destination}/${Reflect.field(translations, locale)}', catalogue);
        }
        manifest.assets = {views: "views"};
    }

    /** Copies a visual design with its draft, its published version and its images. **/
    static function design(sourceId:String, manifestSource:String, name:String, userId:Int,
            userName:String):String {
        var images = Storage.disk("theme_assets");
        var copied:Array<String> = [];
        var committed = false;
        PackageManager.writes.acquire("packages");
        try {
            var saved = ThemeDesign.query.select(["draft", "published"])
                .where("id", sourceId)
                .limit(1)
                .first();
            if (saved == null) {
                throw new Exception("This theme is no longer available.");
            }
            var slug = 'studio-${Md5.encode(SecureToken.generate(32)).substr(0, 12)}';
            var id = 'theme-${slug}';
            if (InstalledPackage.query.where("id", id).exists()) {
                throw new Exception("This design identifier is already in use. Try again.");
            }
            // The copy's images live under its own ID, so every reference moves with them.
            var replacements = [ThemeAssets.prefix(sourceId) => ThemeAssets.prefix(id)];
            var draft = moved(saved.draft, replacements);
            var published:Null<Dynamic> = saved.published == "" ? null : moved(saved.published,
                replacements);
            var manifest:Dynamic = Json.parse(manifestSource);
            manifest.slug = slug;
            manifest.name = name;
            manifest.author = userName;
            var now = SiteSettingsStore.timestamp();
            var dependencies = MediaDependencies.forTheme(slug);
            var write = () -> ThemeAssets.locked(id, () -> ThemeAssets.locked(sourceId, () -> {
                var assets = ThemeAsset.query.select(["filename", "title", "alt", "mime_type", "width", "height", "size", "sha256"])
                    .where("theme_id", sourceId)
                    .orderBy("id")
                    .limit(ThemeAssets.MAX_ASSETS + 1)
                    .get();
                if (assets.length > ThemeAssets.MAX_ASSETS) {
                    throw new Exception("The theme has more images than a theme may keep.");
                }
                for (asset in assets) {
                    var from = '${sourceId}/${asset.filename}';
                    var to = '${id}/${asset.filename}';
                    if (!ThemeAssets.validFilename(asset.filename) || !images.fileExists(from)) {
                        throw new Exception("A theme image is missing.");
                    }
                    images.copy(from, to);
                    copied.push(to);
                }
                DBStatic.transaction(() -> {
                    InstalledPackage.query.insert([
                        "id" => id,
                        "kind" => "theme",
                        "slug" => slug,
                        "name" => name,
                        "name_key" => CategoryData.key(name),
                        "version" => manifest.version,
                        "description" => manifest.description ?? "",
                        "author" => userName,
                        "directory" => slug,
                        "manifest" => Json.stringify(manifest),
                        "enabled" => 0,
                        "setting_count" => 0,
                        "settings" => "{}",
                        "last_error" => "",
                        "restart_required" => 0,
                        "installed_at" => now,
                        "updated_at" => now
                    ]);
                    ThemeDesign.query.insert([
                        "id" => id,
                        "draft" => Json.stringify(draft),
                        "published" => published == null ? "" : Json.stringify(published),
                        "version" => 1,
                        "published_version" => published == null ? 0 : 1,
                        "updated_at" => now
                    ]);
                    for (asset in assets) {
                        ThemeAsset.query.insert([
                            "theme_id" => id,
                            "filename" => asset.filename,
                            "title" => asset.title,
                            "alt" => asset.alt,
                            "mime_type" => asset.mime_type,
                            "width" => asset.width,
                            "height" => asset.height,
                            "size" => asset.size,
                            "sha256" => asset.sha256,
                            "created_at" => now
                        ]);
                    }
                    ThemeAssets.requireDesign(id, draft);
                    if (published != null) {
                        ThemeAssets.requireDesign(id, published);
                    }
                    Activity.append(userId, userName, "created", "theme", 0, name);
                });
                committed = true;
                return true;
            }));
            dependencies.withValue("design-draft", draft, () -> {
                return published == null ? write() : dependencies.withValue("design-published",
                    published, write, '${name} (published design)');
            }, '${name} (design draft)');
            ContentCache.changed("extensions");
            ThemeAssets.changed(id);
            PackageManager.writes.release("packages");
            return id;
        } catch (error:Dynamic) {
            if (!committed) {
                for (path in copied) {
                    images.delete(path);
                }
            }
            PackageManager.writes.release("packages");
            throw error;
        }
    }

    static function moved(source:String, replacements:Map<String, String>):Dynamic {
        var document = ThemeDesignSchema.parse(source);
        return ThemeDesignSchema.parse(Json.stringify(ThemeDesignPackage.rewrite(document,
            replacements)));
    }
}
