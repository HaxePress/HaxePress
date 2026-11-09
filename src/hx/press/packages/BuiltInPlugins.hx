package hx.press.packages;

import haxe.Exception;
import haxe.crypto.Sha256;
import hx.press.CmsVersion;
import hx.press.model.InstalledPackage;
import hx.press.model.Setting;
import hx.press.packages.PackageManifest.ManifestData;
import hx.well.facades.Storage;

/** Installed with the site and upgraded from the archives shipped with the application. */
typedef BundledPlugin = {
    var slug:String;
    var identity:String;
    var entrypoint:String;
}

class BuiltInPlugins {
    static final defaults:Array<BundledPlugin> = [
        {
            slug: "rss",
            identity: "3e7d160d-52ba-47ab-860b-e91c1a33b826",
            entrypoint: "extensions.rss.RssPlugin"
        },
        {
            slug: "newsletter",
            identity: "7a6695a4-bc82-4d96-8df6-14a6435837bb",
            entrypoint: "extensions.newsletter.NewsletterPlugin"
        },
        {
            slug: "cloudflare",
            identity: "e36ea9f4-dfb0-4c29-ad55-113f3abe5aca",
            entrypoint: "extensions.cloudflare.CloudflarePlugin"
        },
        {
            slug: "view-count",
            identity: "d47e7c67-745e-4783-8c9c-1d95c3931ab0",
            entrypoint: "extensions.viewcount.ViewCountPlugin"
        },
        #if jvm
        {
            slug: "site-backup",
            identity: "4731896a-89e5-4321-bdb1-565f752d3fb5",
            entrypoint: "extensions.backup.BackupPlugin"
        }
        #end
    ];

    /** The plugins shipped with the application. **/
    public static function bundles():Array<BundledPlugin> {
        return defaults.copy();
    }

    /** The archive of a bundled plugin on the `bundled` disk, built with this version. **/
    public static function archive(bundle:BundledPlugin):String {
        return '${bundle.slug}-${CmsVersion.version}.zip';
    }

    public static function isBuiltIn(id:String, pluginId:Null<String>):Bool {
        return Lambda.exists(defaults,
            bundle -> 'plugin-${bundle.slug}' == id && bundle.identity == pluginId);
    }

    public static function requireUploadable(id:String, manifest:ManifestData, bundled:Bool):Void {
        for (bundle in defaults) {
            var reservedId = 'plugin-${bundle.slug}';
            if (reservedId != id && bundle.identity != manifest.pluginId) {
                continue;
            }
            if (!bundled
                || reservedId != id
                || bundle.identity != manifest.pluginId
                || bundle.entrypoint != manifest.entrypoint) {
                throw new Exception("Bundled plugins are updated with HaxePress.");
            }
            return;
        }
    }

    public static function ensure():Void {
        var disk = Storage.disk("bundled");
        for (bundle in defaults) {
            var id = 'plugin-${bundle.slug}';
            var path = archive(bundle);
            if (!disk.fileExists(path)) {
                continue;
            }
            // Read without the content cache: a restart must not rewrite cached entries.
            var installed = InstalledPackage.query.select(["plugin_id", "manifest"])
                .where("id", id)
                .limit(1)
                .first();
            if (installed != null && installed.plugin_id != bundle.identity) {
                var manifest = PackageManifest.parse(installed.manifest);
                if (installed.plugin_id != null || manifest.entrypoint != bundle.entrypoint) {
                    trace('A different plugin occupies the bundled package ID ${id}.');
                    continue;
                }
            }
            var bytes = disk.getBytes(path);
            var digest = Sha256.make(bytes).toHex();
            var marker = 'cms_builtin_${bundle.slug}';
            if (installed != null
                && installed.plugin_id == bundle.identity
                && Setting.query.where("key", marker).where("value", digest).exists()) {
                continue;
            }
            var inspection = PackageManager.stage(bytes, "plugin", 0, true);
            PackageManager.install(inspection.key, "plugin", 0, "System", installed != null, true);
            if (installed == null) {
                if (bundle.slug == "newsletter") {
                    var title = Setting.query.select(["value"])
                        .where("key", "newsletter_title")
                        .limit(1)
                        .first();
                    if (title != null && title.value != "") {
                        PackageManager.configure(id, ["title" => title.value], [], 0, "System");
                    }
                }
                PackageManager.enable(id, 0, "System");
            }
            Setting.query.upsert(["key" => marker, "value" => digest], ["key"], ["value"]);
        }
    }
}
