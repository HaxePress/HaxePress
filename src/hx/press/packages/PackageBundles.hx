package hx.press.packages;

import hx.press.model.InstalledPackage;
import hx.press.model.Setting;
import hx.well.facades.Storage;
import hx.press.CmsVersion;

class PackageBundles {
    public static function ensure():Void {
        BuiltInTheme.ensure();
        ensureThemes();
        ensureFeatures();
        upgradeCmsRelease();
        ensureTranslations();
    }

    static function upgradeCmsRelease():Void {
        var marker = 'cms_bundles_${CmsVersion.version}_api_${CmsVersion.pluginApiVersion}';
        if (Setting.query.where("key", marker).exists()) {
            return;
        }
        var bundles = [
            {slug: "fieldnotes", kind: "theme", entrypoint: ""},
            {slug: "notebook", kind: "theme", entrypoint: ""},
            {slug: "gallery", kind: "theme", entrypoint: ""},
            {slug: "rss", kind: "plugin", entrypoint: "extensions.rss.RssPlugin"},
            {
                slug: "newsletter",
                kind: "plugin",
                entrypoint: "extensions.newsletter.NewsletterPlugin"
            },
            {slug: "reading-companion", kind: "plugin", entrypoint: "example.reading.ReadingPlugin"}
        ];
        for (bundle in bundles) {
            var installed = PackageData.one('${bundle.kind}-${bundle.slug}');
            if (installed == null) {
                continue;
            }
            var manifest = PackageManifest.parse(installed.manifest);
            if (manifest.cmsVersion == CmsVersion.version
                && manifest.apiVersion == CmsVersion.pluginApiVersion) {
                continue;
            }
            if (!["Fieldnotes", "HxWell CMS", "HaxePress"].contains(manifest.author)
                || manifest.entrypoint != bundle.entrypoint) {
                continue;
            }
            var filename = 'packages/${bundle.slug}-${CmsVersion.version}.zip';
            var disk = Storage.disk("public");
            if (!disk.fileExists(filename)) {
                return;
            }
            var inspection = PackageManager.stage(disk.getBytes(filename), bundle.kind, 0);
            PackageManager.install(inspection.key, bundle.kind, 0, "System", true);
        }
        Setting.query.insert(["key" => marker, "value" => CmsVersion.version]);
    }

    static function ensureFeatures():Void {
        if (Setting.query.where("key", "cms_feature_plugins_v1").exists()) {
            return;
        }
        for (slug in ["rss", "newsletter"]) {
            var id = 'plugin-${slug}';
            if (InstalledPackage.query.where("id", id).exists()) {
                continue;
            }
            var path = 'packages/${slug}-${CmsVersion.version}.zip';
            if (!Storage.disk("public").fileExists(path)) {
                return;
            }
            var inspection = PackageManager.stage(Storage.disk("public").getBytes(path), "plugin",
                0);
            PackageManager.install(inspection.key, "plugin", 0, "System", false);
            if (slug == "newsletter") {
                var legacy = Setting.query.select(["value"])
                    .where("key", "newsletter_title")
                    .limit(1)
                    .first();
                if (legacy != null && legacy.value != "") {
                    PackageManager.configure(id, ["title" => legacy.value], [], 0, "System");
                }
            }
            PackageManager.enable(id, 0, "System");
        }
        Setting.query.insert(["key" => "cms_feature_plugins_v1", "value" => CmsVersion.version]);
    }

    static function ensureTranslations():Void {
        if (Setting.query.where("key", "cms_bundled_translations_v1").exists()) {
            return;
        }
        for (slug in ["rss", "newsletter", "fieldnotes", "notebook", "gallery"]) {
            var kind = ["rss", "newsletter"].contains(slug) ? "plugin" : "theme";
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
