package hx.press.packages;

import hx.press.themes.ThemeAssets;
import hx.press.media.MediaLocks;
import hx.press.CategoryData;
import hx.press.ContentCache;
import hx.press.SiteSettingsStore;
import hx.press.navigation.NavigationRegions;
import hx.press.Activity;
import hx.press.packages.PackageData.PackageRecord;
import hx.press.plugins.PluginRuntime;
import haxe.Exception;
import haxe.Json;
import haxe.io.Bytes;
import hx.well.facades.DBStatic;
import hx.well.internal.SecureToken;
import hx.press.model.InstalledPackage;
import hx.press.model.PackageHook;
import hx.press.model.PackageUpload;
import hx.well.thread.MutexPool;
import hx.well.facades.Storage;
import hx.press.model.ThemeDesign;
import hx.press.media.MediaDependencies;
#if jvm
import hx.press.themes.ThemeDesignPackage;
#end
import hx.press.model.ThemeAiConnection;

class PackageManager {
    public static final writes = new MutexPool();

    public static function stage(bytes:Bytes, kind:String, userId:Int):Dynamic {
        if (PackageUpload.query.where("user_id", userId)
            .where("expires_epoch", ">", Date.now().getTime())
            .count() >= 5) {
            throw new Exception("Finish or discard your previous package uploads before uploading another.");
        }
        var token = SecureToken.generate(32);
        var destination = PackageStorage.STAGING + "/" + token;
        var inspected = SafePackageArchive.extract(bytes, destination);
        try {
            if (inspected.manifest.kind != kind) {
                throw new Exception("Upload a " + kind + " package in this section.");
            }
            BuiltInTheme.requireUploadable(kind + "-" + inspected.manifest.slug);
            var source = Storage.disk("extensions")
                .get(inspected.root + "/" + PackageManifest.FILENAME);
            PackageUpload.query.create([
                "key" => token,
                "user_id" => userId,
                "kind" => kind,
                "directory" => inspected.root,
                "manifest" => source,
                "expires_epoch" => Date.now().getTime() + 3600000
            ]);
            var id = kind + "-" + inspected.manifest.slug;
            var existing = InstalledPackage.query.select(["version"])
                .where("id", id)
                .limit(1)
                .first();
            return {
                key: token,
                manifest: inspected.manifest,
                serverTarget: PackageManifest.serverArtifact(inspected.manifest) == "" ? "" : PackageManifest.serverTarget(),
                installedVersion: existing == null ? null : existing.version
            };
        } catch (error:Dynamic) {
            PackageStorage.remove(destination);
            throw error;
        }
    }

    public static function discard(token:String, userId:Int):Void {
        var upload = PackageUpload.query.where("key", token)
            .where("user_id", userId)
            .limit(1)
            .first();
        if (upload != null) {
            PackageStorage.remove(upload.directory);
            upload.delete();
        }
    }

    static function record(id:String):PackageRecord {
        var row = InstalledPackage.query.select([
            "id",
            "kind",
            "slug",
            "name",
            "version",
            "directory",
            "manifest",
            "settings",
            "enabled",
            "restart_required"
        ]).where("id", id).first();
        if (row == null) {
            throw new Exception("The installed package could not be found.");
        }
        return cast row.toObject();
    }

    static function actor(userId:Int, name:String):Dynamic {
        return {user: {id: userId, name: name}};
    }

    public static function install(token:String, kind:String, userId:Int, name:String,
            replace:Bool):String {
        writes.acquire("packages");
        var moved:String = null;
        var committed = false;
        try {
            var upload = PackageUpload.query.where("key", token)
                .where("user_id", userId)
                .where("kind", kind)
                .where("expires_epoch", ">", Date.now().getTime())
                .limit(1)
                .first();
            if (upload == null) {
                throw new Exception("This package upload has expired. Upload the ZIP again.");
            }
            var manifest = PackageManifest.parse(upload.manifest);
            PackageManifest.requireCompatible(manifest);
            var id = kind + "-" + manifest.slug;
            BuiltInTheme.requireUploadable(id);
            var previous = InstalledPackage.query.where("id", id).limit(1).first();
            if (previous != null && !replace) {
                throw new Exception("This package is already installed. Choose Replace package to update it.");
            }
            if (previous != null && previous.restart_required == 1) {
                throw new Exception("Restart the server before replacing this plugin.");
            }
            if (manifest.layout == "builder") {
                #if jvm
                var installed = ThemeDesignPackage.install(upload, manifest, previous, userId,
                    name);
                writes.release("packages");
                return installed;
                #else
                throw new Exception("Visual theme package installation requires the JVM host.");
                #end
            }
            if (ThemeDesign.query.where("id", id).exists()) {
                throw new Exception("A packaged renderer cannot replace a visual theme design.");
            }
            var settings = PackageSettings.defaults(manifest);
            var wasEnabled = previous != null && previous.enabled == 1;
            var previousDirectory = previous == null ? null : previous.directory;
            if (previous != null) {
                var oldManifest = PackageManifest.parse(previous.manifest);
                var oldValues = PackageSettings.stored(previous.settings);
                for (field in manifest.fields) {
                    var matching = oldManifest.fields.filter(candidate -> candidate.key == field.key
                        && candidate.kind == field.kind);
                    if (matching.length == 1 && oldValues.exists(field.key)) {
                        settings.set(field.key, oldValues.get(field.key));
                    }
                }
                if (wasEnabled) {
                    InstalledPackage.query.where("id", id).update(["enabled" => 0]);
                    ContentCache.changed("extensions");
                    if (PluginRuntime.ready) {
                        PluginRuntime.stop(record(id));
                    }
                }
            }
            var enabled = wasEnabled ? 1 : 0;
            var serialized = Json.stringify(settings);
            if (enabled == 1) {
                try {
                    PackageSettings.ready(manifest, serialized);
                } catch (invalid:Dynamic) {
                    enabled = 0;
                }
            }
            var directory = id + "-" + manifest.version + "-" + SecureToken.generate(16);
            moved = PackageStorage.installed(directory);
            PackageStorage.installFrom(upload.directory, moved);
            var now = SiteSettingsStore.timestamp();
            var values:Map<String, Dynamic> = [
                "id" => id,
                "kind" => kind,
                "slug" => manifest.slug,
                "name" => manifest.name,
                "name_key" => CategoryData.key(manifest.name),
                "version" => manifest.version,
                "description" => manifest.description,
                "author" => manifest.author,
                "directory" => directory,
                "manifest" => upload.manifest,
                "settings" => serialized,
                "enabled" => enabled,
                "setting_count" => manifest.fields.length,
                "last_error" => "",
                "restart_required" => 0,
                "installed_at" => previous == null ? now : previous.installed_at,
                "updated_at" => now
            ];
            MediaLocks.run(() -> {
                DBStatic.transaction(() -> {
                    if (previous == null) {
                        InstalledPackage.query.create(values);
                    } else {
                        previous.update(values);
                        PackageHook.query.where("package_id", id).delete();
                    }
                    for (event in manifest.hooks) {
                        PackageHook.query.create(["package_id" => id, "event" => event]);
                    }
                    upload.delete();
                    Activity.append(userId, name, previous == null ? "installed" : "updated",
                        kind, 0, manifest.name);
                });
                return true;
            });
            committed = true;
            ContentCache.changed("extensions");
            if (previous != null) {
                PackageStorage.remove(PackageStorage.installed(previousDirectory));
            }
            PackageStorage.remove(PackageStorage.STAGING + "/" + token);
            if (enabled == 1 && PluginRuntime.ready) {
                PluginRuntime.start(record(id));
            }
            writes.release("packages");
            return id;
        } catch (error:Dynamic) {
            if (!committed && moved != null && Storage.disk("extensions").directoryExists(moved)) {
                PackageStorage.remove(moved);
                PackageUpload.query.where("key", token).where("user_id", userId).delete();
                PackageStorage.remove(PackageStorage.STAGING + "/" + token);
            }
            writes.release("packages");
            throw error;
        }
    }

    public static function enable(id:String, userId:Int, name:String):Void {
        writes.acquire("packages");
        try {
            var packageData = record(id);
            var manifest = PackageManifest.parse(packageData.manifest);
            PackageManifest.requireCompatible(manifest);
            if (manifest.layout == "builder"
                && !ThemeDesign.query.where("id", id).where("published_version", ">", 0).exists()) {
                throw new Exception("Publish this theme in the theme builder before activating it.");
            }
            if (packageData.restart_required == 1) {
                throw new Exception("Restart the server before activating this plugin again.");
            }
            PackageSettings.ready(manifest, packageData.settings);
            if (packageData.kind == "theme") {
                for (region in manifest.navigation) {
                    NavigationRegions.ensure(region.key, region.name, region.maxLinks);
                }
            }
            if (packageData.enabled == 1) {
                writes.release("packages");
                return;
            }
            if (packageData.kind == "plugin"
                && InstalledPackage.query.where("kind", "plugin")
                    .where("enabled", 1)
                    .count() >= PackageData.MAX_ACTIVE_PLUGINS) {
                throw new Exception("Disable an active plugin before enabling more than 32 plugins.");
            }
            var previousTheme = packageData.kind == "theme" ? PackageData.activeTheme() : null;
            if (previousTheme != null && PluginRuntime.ready) {
                PluginRuntime.stop(previousTheme);
            }
            DBStatic.transaction(() -> {
                if (packageData.kind == "theme") {
                    InstalledPackage.query.where("kind", "theme")
                        .where("enabled", 1)
                        .update(["enabled" => 0]);
                }
                InstalledPackage.query.where("id", id).update([
                    "enabled" => 1,
                    "last_error" => "",
                    "updated_at" => SiteSettingsStore.timestamp()
                ]);
                Activity.append(userId, name, "activated", packageData.kind, 0, packageData.name);
            });
            ContentCache.changed("extensions");
            if (PluginRuntime.ready) {
                PluginRuntime.start(record(id));
            }
            writes.release("packages");
        } catch (error:Dynamic) {
            writes.release("packages");
            throw error;
        }
    }

    public static function disable(id:String, userId:Int, name:String):Void {
        writes.acquire("packages");
        try {
            var packageData = record(id);
            if (packageData.kind == "theme") {
                throw new Exception("Activate another theme before changing the active theme.");
            }
            DBStatic.transaction(() -> {
                InstalledPackage.query.where("id", id)
                    .update(["enabled" => 0, "updated_at" => SiteSettingsStore.timestamp()]);
                Activity.append(userId, name, "deactivated", packageData.kind, 0, packageData.name);
            });
            ContentCache.changed("extensions");
            if (PluginRuntime.ready) {
                PluginRuntime.stop(packageData);
            }
            writes.release("packages");
        } catch (error:Dynamic) {
            writes.release("packages");
            throw error;
        }
    }

    public static function configure(id:String, input:Map<String, String>, clear:Array<String>,
            userId:Int, name:String):Void {
        writes.acquire("packages");
        try {
            var packageData = record(id);
            var manifest = PackageManifest.parse(packageData.manifest);
            PackageManifest.requireCompatible(manifest);
            var settings = PackageSettings.prepare(manifest, packageData.settings, input, clear);
            var configured:PackageRecord = cast Reflect.copy(packageData);
            configured.settings = Json.stringify(settings);
            if (packageData.enabled == 1) {
                PackageSettings.ready(manifest, configured.settings);
                if (PluginRuntime.ready) {
                    PluginRuntime.invoke(configured, "settings.saved", actor(userId, name), true);
                }
            }
            MediaLocks.run(() -> {
                DBStatic.transaction(() -> {
                    InstalledPackage.query.where("id", id)
                        .update(["settings" => configured.settings, "updated_at" => SiteSettingsStore.timestamp()]);
                    Activity.append(userId, name, "configured", packageData.kind, 0,
                        packageData.name);
                });
                return true;
            });
            ContentCache.changed("extensions");
            writes.release("packages");
        } catch (error:Dynamic) {
            writes.release("packages");
            throw error;
        }
    }

    public static function uninstall(id:String, userId:Int, name:String):Void {
        writes.acquire("packages");
        try {
            if (BuiltInTheme.isBuiltIn(id)) {
                throw new Exception("The built-in theme is included with HaxePress and cannot be uninstalled.");
            }
            var packageData = record(id);
            if (packageData.kind == "theme" && packageData.enabled == 1) {
                throw new Exception("Activate another theme before removing this theme.");
            }
            InstalledPackage.query.where("id", id).update(["enabled" => 0]);
            ContentCache.changed("extensions");
            if (PluginRuntime.ready) {
                PluginRuntime.stop(packageData);
            }
            MediaLocks.run(() -> ThemeAssets.locked(id, () -> {
                DBStatic.transaction(() -> {
                    PackageHook.query.where("package_id", id).delete();
                    ThemeDesign.query.where("id", id).delete();
                    ThemeAiConnection.query.where("theme_id", id).delete();
                    InstalledPackage.query.where("id", id).delete();
                    Activity.append(userId, name, "uninstalled", packageData.kind, 0,
                        packageData.name);
                });
                if (packageData.kind == "theme") {
                    var dependencies = MediaDependencies.forTheme(packageData.slug);
                    dependencies.forget("design-draft");
                    dependencies.forget("design-published");
                    var imageDisk = Storage.disk("theme_assets");
                    if (imageDisk.directoryExists(id)) {
                        imageDisk.deleteDirectory(id);
                    }
                    ThemeAssets.changed(id);
                }
                return true;
            }));
            ContentCache.changed("extensions");
            PackageStorage.remove(PackageStorage.installed(packageData.directory));
            writes.release("packages");
        } catch (error:Dynamic) {
            writes.release("packages");
            throw error;
        }
    }

    public static function cleanupUploads():Void {
        writes.acquire("packages");
        try {
            var expired = PackageUpload.query.select(["key", "directory"])
                .where("expires_epoch", "<=", Date.now().getTime())
                .orderBy("key")
                .limit(20)
                .get();
            for (upload in expired) {
                PackageStorage.remove(upload.directory);
                upload.delete();
            }
            writes.release("packages");
        } catch (error:Dynamic) {
            writes.release("packages");
            throw error;
        }
    }
}
