package hx.press.packages;

import haxe.Exception;
import haxe.Json;
import haxe.Resource;
import hx.press.CategoryData;
import hx.press.ContentCache;
import hx.press.SiteSettingsStore;
import hx.press.model.InstalledPackage;
import hx.press.model.PackageHook;
import hx.well.facades.DBStatic;

/** The default theme belongs to the application, rather than an uploaded package directory. */
class BuiltInTheme {
    public static inline var ID = "theme-simple";
    public static inline var RESOURCE = "hx.press.theme.simple";

    public static function isBuiltIn(id:String):Bool {
        return id == ID;
    }

    public static function requireUploadable(id:String):Void {
        if (isBuiltIn(id)) {
            throw new Exception("The built-in theme is updated with HaxePress and cannot be replaced by a ZIP package.");
        }
    }

    public static function translations(locale:String):Null<String> {
        return Resource.getString('${RESOURCE}.lang.${locale}');
    }

    public static function ensure():Void {
        var source = Resource.getString(RESOURCE);
        if (source == null) {
            throw new Exception("The application's built-in theme resource is missing.");
        }
        var manifest = PackageManifest.parse(source);
        PackageManifest.requireCompatible(manifest);
        var packageQuery = InstalledPackage.query.where("id", ID);
        var current = packageQuery.select([
            "kind",
            "manifest",
            "directory",
            "last_error",
            "restart_required",
            "settings",
            "enabled",
            "installed_at"
        ]).first();
        if (current != null && current.kind == "theme" && current.manifest == source
            && current.directory == "" && current.last_error == "" && current.restart_required == 0) {
            return;
        }
        var stored = current == null ? "{}" : current.settings;
        var previous = PackageSettings.values(manifest, stored, true);
        var settings = PackageSettings.prepare(manifest, stored, previous, []);
        var enabled = 1;
        if (current != null) {
            enabled = current.enabled;
        } else {
            var otherThemeActive = InstalledPackage.query.where("kind", "theme")
                .where("enabled", 1)
                .exists();
            if (otherThemeActive) {
                enabled = 0;
            }
        }
        var now = SiteSettingsStore.timestamp();
        var values:Map<String, Dynamic> = [
            "kind" => "theme",
            "slug" => manifest.slug,
            "name" => manifest.name,
            "name_key" => CategoryData.key(manifest.name),
            "version" => manifest.version,
            "description" => manifest.description,
            "author" => manifest.author,
            "directory" => "",
            "manifest" => source,
            "settings" => Json.stringify(settings),
            "enabled" => enabled,
            "setting_count" => manifest.fields.length,
            "last_error" => "",
            "restart_required" => 0,
            "installed_at" => current == null ? now : current.installed_at,
            "updated_at" => now
        ];
        DBStatic.transaction(() -> {
            if (packageQuery.exists()) {
                packageQuery.update(values);
            } else {
                values.set("id", ID);
                InstalledPackage.query.insert(values);
            }
            PackageHook.query.where("package_id", ID).delete();
            for (event in manifest.hooks) {
                PackageHook.query.insert(["package_id" => ID, "event" => event]);
            }
        });
        ContentCache.changed("extensions");
    }
}
