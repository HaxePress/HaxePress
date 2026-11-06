package hx.press.themes;

import haxe.Exception;
import haxe.Json;
import haxe.crypto.Sha256;
import haxe.io.Bytes;
import haxe.io.BytesInput;
import haxe.io.Eof;
import hx.press.Activity;
import hx.press.CategoryData;
import hx.press.CmsVersion;
import hx.press.ContentCache;
import hx.press.SiteSettingsStore;
#if jvm
import hx.press.MediaStorage;
#end
import hx.press.media.MediaDependencies;
import hx.press.media.MediaLocks;
import hx.press.media.MediaReferences;
import hx.press.model.InstalledPackage;
import hx.press.model.MediaAsset;
import hx.press.model.PackageUpload;
import hx.press.model.ThemeDesign;
import hx.press.model.ThemeAsset;
import hx.press.packages.PackageArchiveInput;
import hx.press.packages.PackageArchiveInput.ArchiveSource;
import hx.press.packages.PackageManifest;
import hx.press.packages.PackageManifest.ManifestData;
import hx.press.packages.PackageStorage;
import hx.press.packages.SafePackageArchive;
import hx.press.storage.TemporaryDownloadInput;
import hx.well.facades.DBStatic;
import hx.well.facades.Storage;
import hx.well.http.InputResponse;
import hx.well.internal.SecureToken;
import hx.well.storage.StorageDisk;

using Lambda;

typedef ThemePackageMedia = {
    var filename:String;
    var title:String;
    var alt:String;
}

class ThemeDesignPackage {
    public static inline var DESIGN = "theme-design.json";
    public static inline var MEDIA = "theme-media.json";
    static inline var MEDIA_METADATA_BYTES = 512 * 1024;

    static function read(disk:StorageDisk, path:String, maximum:Int):Bytes {
        if (!disk.fileExists(path)) {
            throw new Exception("A required theme package file is missing.");
        }
        var size = disk.size(path);
        if (size < 0 || size > maximum) {
            throw new Exception("A theme package file exceeds its size limit.");
        }
        var input = disk.readStream(path);
        try {
            var bytes = Bytes.alloc(size);
            input.readFullBytes(bytes, 0, size);
            var extra = false;
            try {
                input.readByte();
                extra = true;
            } catch (_:Eof) {}
            if (extra) {
                throw new Exception("A theme package file changed while it was being read.");
            }
            input.close();
            return bytes;
        } catch (error:Dynamic) {
            input.close();
            throw error;
        }
    }

    static function textSource(name:String, value:Dynamic):ArchiveSource {
        var bytes = Bytes.ofString(Json.stringify(value));
        return {name: name, size: bytes.length, open: () -> new BytesInput(bytes)};
    }

    public static function download(id:String, name:String = "", source:String = ""):InputResponse {
        var item = InstalledPackage.query.select(["id", "slug", "name", "version", "description", "author"])
            .where("id", id)
            .where("kind", "theme")
            .limit(1)
            .first();
        var saved = source == "" ? ThemeDesign.query.select(["draft"])
            .where("id", id)
            .limit(1)
            .first() : null;
        var available = saved != null
            || (source != "" && ThemeDesign.query.where("id", id).exists());
        if (item == null || !available) {
            throw new Exception("Choose a theme created in the visual editor.");
        }
        var document = ThemeDesignSchema.parse(source == "" ? saved.draft : source);
        var themeName = name == "" ? item.name : name;
        var manifest:Dynamic = {
            apiVersion: CmsVersion.pluginApiVersion,
            cmsVersion: CmsVersion.version,
            kind: "theme",
            slug: item.slug,
            name: themeName,
            version: item.version,
            description: item.description,
            author: item.author,
            layout: "builder",
            design: {
                file: DESIGN,
                media: MEDIA,
                mediaPrefix: ThemeAssets.prefix(id)
            },
            templates: ThemeStudio.templateDefinitions(document),
            hooks: [],
            fields: []
        };
        PackageManifest.parse(Json.stringify(manifest));
        var disk = Storage.disk("exports");
        var path = '${SecureToken.generate(32)}.zip';
        try {
            MediaLocks.run(() -> ThemeAssets.locked(id, () -> {
                ThemeAssets.requireDesign(id, document);
                var owned = ThemeAsset.query.select(["filename", "title", "alt"])
                    .where("theme_id", id)
                    .orderBy("filename")
                    .limit(ThemeAssets.MAX_ASSETS + 1)
                    .get()
                    .map(model -> cast model.toObject());
                var filenames = MediaDependencies.filenames(document);
                var legacy:Array<ThemePackageMedia> = filenames.length == 0 ? [] : MediaAsset.query.select(["filename", "title", "alt"])
                    .whereIn("filename", cast filenames)
                    .orderBy("filename")
                    .limit(filenames.length)
                    .get()
                    .map(model -> cast model.toObject());
                if (legacy.length != filenames.length) {
                    throw new Exception("A referenced media image is no longer available.");
                }
                var media:Array<ThemePackageMedia> = [];
                var imageFiles:Array<ArchiveSource> = [];
                var usedNames:Map<String, Bool> = [];
                var replacements:Map<String, String> = [];
                var themeDisk = Storage.disk("theme_assets");
                var mediaDisk = Storage.disk("media");
                var total = 0;
                for (image in (cast owned : Array<ThemePackageMedia>)) {
                    var filename = image.filename;
                    var imagePath = '${id}/${filename}';
                    if (!ThemeAssets.validFilename(filename)
                        || !themeDisk.fileExists(imagePath)
                        || themeDisk.size(imagePath) > MediaReferences.MAX_BYTES) {
                        throw new Exception("A theme image is missing or exceeds its size limit.");
                    }
                    usedNames.set(filename, true);
                    media.push(image);
                    total += themeDisk.size(imagePath);
                    imageFiles.push({
                        name: 'media/${filename}',
                        size: themeDisk.size(imagePath),
                        open: () -> themeDisk.readStream(imagePath)
                    });
                }
                for (image in legacy) {
                    var original = image.filename;
                    if (!MediaReferences.validFilename(original)
                        || !mediaDisk.fileExists(original)
                        || mediaDisk.size(original) > MediaReferences.MAX_BYTES) {
                        throw new Exception("A referenced media image is missing or exceeds its size limit.");
                    }
                    var filename = ThemeAssets.packagedFilename(original);
                    while (usedNames.exists(filename)) {
                        filename = 'ta_${SecureToken.generate(32)}${original.substr(32)}';
                    }
                    usedNames.set(filename, true);
                    replacements.set('${MediaReferences.prefix()}${original}',
                        ThemeAssets.url(id, filename));
                    media.push({filename: filename, title: image.title, alt: image.alt});
                    total += mediaDisk.size(original);
                    imageFiles.push({
                        name: 'media/${filename}',
                        size: mediaDisk.size(original),
                        open: () -> mediaDisk.readStream(original)
                    });
                }
                if (media.length > ThemeAssets.MAX_ASSETS || total > ThemeAssets.MAX_TOTAL_BYTES) {
                    throw new Exception("The theme images exceed the export package budget.");
                }
                var exported = rewrite(document, replacements);
                var files = [
                    textSource(PackageManifest.FILENAME, manifest),
                    textSource(DESIGN, exported),
                    textSource(MEDIA, media)
                ].concat(imageFiles);
                var archive = new PackageArchiveInput(files);
                try {
                    disk.writeStream(path, archive);
                    archive.close();
                } catch (error:Dynamic) {
                    archive.close();
                    throw error;
                }
                return true;
            }));
            var filename = ~/[^a-z0-9]+/g.replace(CategoryData.key(themeName), "-");
            filename = ~/^-+|-+$/g.replace(filename, "").substr(0, 80);
            if (filename == "") {
                filename = item.slug;
            }
            var response = disk.download(path, '${filename}-${item.version}.zip',
                ["Content-Type" => "application/zip", "Cache-Control" => "private, no-store"]);
            response.input = new TemporaryDownloadInput(response.input, () -> disk.delete(path));
            return response;
        } catch (error:Dynamic) {
            if (disk.fileExists(path)) {
                disk.delete(path);
            }
            throw error;
        }
    }

    static function rewrite(value:Dynamic, replacements:Map<String, String>,
            depth:Int = 0):Dynamic {
        if (depth > 64) {
            throw new Exception("The theme package contains excessively nested JSON.");
        }
        if (Std.isOfType(value, String)) {
            var result:String = value;
            for (old => replacement in replacements) {
                result = StringTools.replace(result, old, replacement);
            }
            return result;
        }
        if (Std.isOfType(value, Array)) {
            var entries:Array<Dynamic> = value;
            return entries.map(entry -> rewrite(entry, replacements, depth + 1));
        }
        if (value != null && Reflect.isObject(value)) {
            var result:Dynamic = {};
            for (field in Reflect.fields(value)) {
                Reflect.setField(result, field,
                    rewrite(Reflect.field(value, field), replacements, depth + 1));
            }
            return result;
        }
        return value;
    }

    static function metadata(root:String, manifest:ManifestData):Array<ThemePackageMedia> {
        var input:Dynamic = Json.parse(read(Storage.disk("extensions"),
            '${root}/${manifest.mediaFile}', MEDIA_METADATA_BYTES).toString());
        if (!Std.isOfType(input, Array)) {
            throw new Exception("The visual theme media list must be an array.");
        }
        var entries:Array<Dynamic> = input;
        if (entries.length > MediaDependencies.MAX_MEDIA_PER_REFERENCE) {
            throw new Exception("A visual theme package can include up to 128 images.");
        }
        var seen:Map<String, Bool> = [];
        return entries.map(entry -> {
            var filename = PackageManifest.text(entry, "filename", 40, true);
            if ((!MediaReferences.validFilename(filename) && !ThemeAssets.validFilename(filename))
                || seen.exists(ThemeAssets.packagedFilename(filename))) {
                throw new Exception("The visual theme media list contains invalid or duplicate image names.");
            }
            seen.set(ThemeAssets.packagedFilename(filename), true);
            return {
                filename: filename,
                title: PackageManifest.text(entry, "title", 180),
                alt: PackageManifest.text(entry, "alt", 500)
            };
        });
    }

    static function document(root:String, manifest:ManifestData):Dynamic {
        var source = read(Storage.disk("extensions"), '${root}/${manifest.designFile}',
            ThemeDesignSchema.MAX_BYTES).toString();
        var input:Dynamic = Json.parse(source);
        var replacements:Map<String, String> = [];
        for (image in metadata(root, manifest)) {
            replacements.set('${manifest.mediaPrefix}${image.filename}',
                ThemeAssets.url("theme-package", ThemeAssets.packagedFilename(image.filename)));
        }
        var rebased = rewrite(input, replacements);
        return ThemeDesignSchema.parse(Json.stringify(rebased));
    }

    static function imageInfo(bytes:Bytes):{
        extension:String,
        contentType:String,
        width:Int,
        height:Int
    } {
        #if jvm
        var format = MediaStorage.format(bytes);
        if (format == null) {
            throw new Exception("Use JPEG, PNG or GIF for bundled theme images.");
        }
        var dimensions = MediaStorage.dimensions(bytes);
        if (dimensions == null) {
            throw new Exception("A bundled theme image is invalid or exceeds the image dimension limits.");
        }
        return {
            extension: format.extension,
            contentType: format.contentType,
            width: dimensions.width,
            height: dimensions.height
        };
        #else
        throw new Exception("Visual theme image imports require the JVM image driver.");
        #end
    }

    public static function inspect(root:String, manifest:ManifestData):Void {
        if (manifest.designFile == ""
            || manifest.mediaFile == ""
            || manifest.mediaPrefix == ""
            || !StringTools.endsWith(manifest.mediaPrefix, "/")
            || ~/[\x00-\x1f\x7f]/.match(manifest.mediaPrefix)) {
            throw new Exception("A visual theme package requires its design, media list and source media prefix.");
        }
        if (manifest.module != "" || manifest.renderer != "" || manifest.stylesheet != ""
            || PackageManifest.hasServer(manifest) || manifest.fields.length > 0
            || manifest.hooks.length > 0) {
            throw new Exception("Visual theme packages contain a design and images, without executable modules or package settings.");
        }
        var design = document(root, manifest);
        var media = metadata(root, manifest);
        var names = media.map(image -> ThemeAssets.packagedFilename(image.filename));
        for (address => owner in ThemeAssets.references(design)) {
            var filename = address.substr(ThemeAssets.prefix("theme-package").length);
            if (owner != "theme-package" || !names.contains(filename)) {
                throw new Exception("Include every image referenced by the theme design in its image list.");
            }
        }
        if (MediaDependencies.filenames(design).length != 0) {
            throw new Exception("Include every image referenced by the theme design in its image list.");
        }
        var disk = Storage.disk("extensions");
        var total = 0;
        for (image in media) {
            var bytes = read(disk, '${root}/media/${image.filename}', MediaReferences.MAX_BYTES);
            total += bytes.length;
            if (total > ThemeAssets.MAX_TOTAL_BYTES) {
                throw new Exception("The theme images exceed the export package budget.");
            }
            var info = imageInfo(bytes);
            if (!StringTools.endsWith(image.filename, '.${info.extension}')) {
                throw new Exception("A bundled theme image is invalid or exceeds the image dimension limits.");
            }
        }
    }

    /** Called under PackageManager's package lock; files are compensated if the ORM transaction fails. */
    public static function install(upload:PackageUpload, manifest:ManifestData,
            previous:Null<InstalledPackage>, userId:Int, userName:String):String {
        var id = 'theme-${manifest.slug}';
        var current = ThemeDesign.query.select(["version"]).where("id", id).limit(1).first();
        if (previous != null && current == null) {
            throw new Exception("A visual theme cannot replace a theme that uses a packaged renderer.");
        }
        inspect(upload.directory, manifest);
        var design = document(upload.directory, manifest);
        if (previous != null) {
            ThemeStudio.requireTemplates(design, Json.parse(previous.manifest));
        }
        var media = metadata(upload.directory, manifest);
        var created:Array<String> = [];
        var committed = false;
        var images = Storage.disk("theme_assets");
        try {
            MediaLocks.run(() -> ThemeAssets.locked(id, () -> {
                DBStatic.transaction(() -> {
                    var replacements:Map<String, String> = [];
                    var additions:Array<Map<String, Dynamic>> = [];
                    for (image in media) {
                        var bytes = read(Storage.disk("extensions"),
                            '${upload.directory}/media/${image.filename}',
                            MediaReferences.MAX_BYTES);
                        var digest = Sha256.make(bytes).toHex();
                        var canonical = ThemeAssets.packagedFilename(image.filename);
                        var existing = ThemeAsset.query.select(["id", "filename", "sha256", "size"])
                            .where("theme_id", id)
                            .where("filename", canonical)
                            .limit(1)
                            .first();
                        var filename = canonical;
                        var existingPath = '${id}/${filename}';
                        if (existing != null && existing.sha256 == digest
                            && existing.size == bytes.length && images.fileExists(existingPath)) {
                            replacements.set(ThemeAssets.url("theme-package", canonical),
                                ThemeAssets.url(id, filename));
                            continue;
                        }
                        if (existing != null || images.exists(existingPath)) {
                            do {
                                filename = 'ta_${SecureToken.generate(32)}${canonical.substr(35)}';
                            } while (media.exists(image ->
                                ThemeAssets.packagedFilename(image.filename) == filename)
                                || images.exists('${id}/${filename}'));
                        }
                        var info = imageInfo(bytes);
                        var path = '${id}/${filename}';
                        images.put(path, bytes);
                        created.push(path);
                        additions.push([
                            "theme_id" => id,
                            "filename" => filename,
                            "title" => image.title,
                            "alt" => image.alt,
                            "mime_type" => info.contentType,
                            "width" => info.width,
                            "height" => info.height,
                            "size" => bytes.length,
                            "sha256" => digest,
                            "created_at" => SiteSettingsStore.timestamp()
                        ]);
                        replacements.set(ThemeAssets.url("theme-package", canonical),
                            ThemeAssets.url(id, filename));
                    }
                    design = ThemeDesignSchema.parse(Json.stringify(rewrite(design, replacements)));
                    var stored:Dynamic = Json.parse(upload.manifest);
                    Reflect.deleteField(stored, "design");
                    stored.templates = ThemeStudio.templateDefinitions(design);
                    var now = SiteSettingsStore.timestamp();
                    var version = current == null ? 1 : current.version + 1;
                    var packageValues:Map<String, Dynamic> = [
                        "kind" => "theme",
                        "slug" => manifest.slug,
                        "name" => manifest.name,
                        "name_key" => CategoryData.key(manifest.name),
                        "version" => manifest.version,
                        "description" => manifest.description,
                        "author" => manifest.author,
                        "directory" => manifest.slug,
                        "manifest" => Json.stringify(stored),
                        "settings" => "{}",
                        "enabled" => previous == null ? 0 : previous.enabled,
                        "setting_count" => 0,
                        "last_error" => "",
                        "restart_required" => 0,
                        "installed_at" => previous == null ? now : previous.installed_at,
                        "updated_at" => now
                    ];
                    var packageQuery = InstalledPackage.query.where("id", id);
                    if (packageQuery.exists()) {
                        packageQuery.update(packageValues);
                    } else {
                        packageValues.set("id", id);
                        InstalledPackage.query.insert(packageValues);
                    }
                    var serialized = Json.stringify(design);
                    ThemeDesign.query.upsert([
                        "id" => id,
                        "draft" => serialized,
                        "published" => serialized,
                        "version" => version,
                        "published_version" => version,
                        "updated_at" => now
                    ], ["id"],
                        ["draft", "published", "version", "published_version", "updated_at"]);
                    for (values in additions) {
                        ThemeAsset.query.insert(values);
                    }
                    ThemeAssets.requireBudget(id);
                    ThemeAssets.requireDesign(id, design);
                    var dependencies = MediaDependencies.forTheme(manifest.slug);
                    dependencies.withValue("design-draft", design,
                        () -> dependencies.withValue("design-published", design, () -> {
                            upload.delete();
                            Activity.append(userId, userName,
                                previous == null ? "installed" : "updated", "theme", 0,
                                manifest.name);
                            return true;
                        },
                            '${manifest.name} (published design)'),
                        '${manifest.name} (design draft)');
                });
                committed = true;
                return true;
            }));
        } catch (error:Dynamic) {
            if (!committed) {
                for (path in created) {
                    images.delete(path);
                }
            }
            throw error;
        }
        ContentCache.changed("extensions");
        ThemeAssets.changed(id);
        PackageStorage.remove('${PackageStorage.STAGING}/${upload.key}');
        return id;
    }
}
