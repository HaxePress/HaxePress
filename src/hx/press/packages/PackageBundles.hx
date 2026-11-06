package hx.press.packages;

import hx.press.model.InstalledPackage;
import hx.press.model.Setting;
import hx.well.facades.Storage;
import hx.press.CmsVersion;
import hx.press.packages.PackageManifest.ManifestData;

class PackageBundles {
    public static function ensure():Void {
        BuiltInTheme.ensure();
        ensureThemes();
        BuiltInPlugins.ensure();
        retireRendererThemes();
        upgradeCmsRelease();
        ensureTranslations();
    }

    static final examples = [
        {slug: "fieldnotes", kind: "theme", entrypoint: ""},
        {slug: "notebook", kind: "theme", entrypoint: ""},
        {slug: "gallery", kind: "theme", entrypoint: ""},
        {slug: "reading-companion", kind: "plugin", entrypoint: "example.reading.ReadingPlugin"}
    ];

    /** Installed example packages follow the release they shipped with. **/
    static function upgradeCmsRelease():Void {
        var marker = 'cms_bundles_${CmsVersion.version}_api_${CmsVersion.pluginApiVersion}';
        if (Setting.query.where("key", marker).exists()) {
            return;
        }
        for (bundle in examples) {
            var installed = PackageData.one('${bundle.kind}-${bundle.slug}');
            if (installed == null) {
                continue;
            }
            var manifest = PackageManifest.parse(installed.manifest);
            if (manifest.cmsVersion == CmsVersion.version
                && manifest.apiVersion == CmsVersion.pluginApiVersion
                && !manifest.legacyRenderer) {
                continue;
            }
            if (!shipped(manifest, bundle.entrypoint)) {
                continue;
            }
            if (!reinstall(bundle.slug, bundle.kind)) {
                // The archive is missing; try again on the next start.
                return;
            }
        }
        Setting.query.insert(["key" => marker, "value" => CmsVersion.version]);
    }

    /**
        Themes built for the former browser renderer cannot run. The shipped
        examples are reinstalled with their Wellout templates; any other such
        theme is removed, and the built-in theme takes over when it was the
        active one. Runs on every start, so a restored backup is cleaned too.
    **/
    static function retireRendererThemes():Void {
        var themes = InstalledPackage.query.select(["id", "slug", "manifest", "enabled"])
            .where("kind", "theme")
            .whereLike("manifest", '%"renderer"%')
            .limit(64)
            .get();
        for (theme in themes) {
            var manifest = PackageManifest.parse(theme.manifest);
            if (!manifest.legacyRenderer) {
                continue;
            }
            var example = Lambda.find(examples,
                bundle -> bundle.kind == "theme" && bundle.slug == theme.slug);
            try {
                if (example != null && shipped(manifest, example.entrypoint)
                    && reinstall(example.slug, example.kind)) {
                    continue;
                }
            } catch (error:Dynamic) {
                trace('Theme ${theme.id} could not be replaced: ${Std.string(error)}');
            }
            try {
                if (theme.enabled == 1) {
                    PackageManager.enable(BuiltInTheme.ID, 0, "System");
                }
                PackageManager.uninstall(theme.id, 0, "System");
                trace('Removed theme ${theme.id}: it was built for the former browser renderer.');
            } catch (error:Dynamic) {
                trace('Theme ${theme.id} could not be removed: ${Std.string(error)}');
            }
        }
    }

    /** Whether an installed package is one of the examples shipped with HaxePress. **/
    static function shipped(manifest:ManifestData, entrypoint:String):Bool {
        return ["Fieldnotes", "HxWell CMS", "HaxePress"].contains(manifest.author)
            && manifest.entrypoint == entrypoint;
    }

    /** Replaces an installed example with the archive shipped with this release. **/
    static function reinstall(slug:String, kind:String):Bool {
        var filename = 'packages/${slug}-${CmsVersion.version}.zip';
        var disk = Storage.disk("public");
        if (!disk.fileExists(filename)) {
            return false;
        }
        var inspection = PackageManager.stage(disk.getBytes(filename), kind, 0);
        PackageManager.install(inspection.key, kind, 0, "System", true);
        return true;
    }

    static function ensureTranslations():Void {
        if (Setting.query.where("key", "cms_bundled_translations_v1").exists()) {
            return;
        }
        for (slug in ["fieldnotes", "notebook", "gallery"]) {
            var kind = "theme";
            var installed = PackageData.one('${kind}-${slug}');
            if (installed == null) {
                continue;
            }
            var manifest = PackageManifest.parse(installed.manifest);
            if (Lambda.count(manifest.translations) > 0) {
                continue;
            }
            var path = 'packages/${slug}-${CmsVersion.version}.zip';
            if (!Storage.disk("public").fileExists(path)) {
                return;
            }
            var inspection = PackageManager.stage(Storage.disk("public").getBytes(path), kind, 0);
            PackageManager.install(inspection.key, kind, 0, "System", true);
        }
        Setting.query.insert(["key" => "cms_bundled_translations_v1", "value" => CmsVersion.version]);
    }

    static function ensureThemes():Void {
        if (Setting.query.where("key", "cms_bundles_v1").exists()) {
            return;
        }
        for (slug in ["fieldnotes", "notebook", "gallery"]) {
            var id = 'theme-${slug}';
            if (!InstalledPackage.query.where("id", id).exists()) {
                var path = 'packages/${slug}-${CmsVersion.version}.zip';
                if (!Storage.disk("public").fileExists(path)) {
                    return;
                }
                var inspection = PackageManager.stage(Storage.disk("public").getBytes(path),
                    "theme", 0);
                PackageManager.install(inspection.key, "theme", 0, "System", false);
            }
        }
        if (!InstalledPackage.query.where("kind", "theme").where("enabled", 1).exists()) {
            PackageManager.enable(BuiltInTheme.ID, 0, "System");
        }
        Setting.query.insert(["key" => "cms_bundles_v1", "value" => "1"]);
    }
}
