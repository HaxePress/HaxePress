package hx.press.packages;

import haxe.Exception;
import haxe.crypto.Sha256;
import haxe.io.Bytes;
import hx.press.model.InstalledPackage;
import hx.press.model.Setting;
import hx.well.facades.Storage;
import hx.press.CmsVersion;
import hx.press.packages.PackageManifest.ManifestData;

/**
    The packages shipped in `public/packages`. Bundled themes belong to the
    application: they are always installed, follow the archives of the
    running build and cannot be replaced or removed; a fork is changed
    instead. The example plugin is optional, and once installed it follows
    the shipped archive too. Settings and activation are kept.
**/
class PackageBundles {
    static final themes = ["fieldnotes", "notebook", "gallery"];
    static final plugins = [
        {
            slug: "reading-companion",
            entrypoint: "example.reading.ReadingPlugin"
        }
    ];

    public static function ensure():Void {
        BuiltInTheme.ensure();
        BuiltInPlugins.ensure();
        retireRendererThemes();
        ensureThemes();
        upgradePlugins();
    }

    /** Whether an installed theme is one of the themes shipped with HaxePress. **/
    public static function isBundledTheme(id:String, author:String):Bool {
        return bundledThemeId(id) && shippedAuthor(author);
    }

    /** Uploads cannot replace a bundled theme; its fork can be changed instead. **/
    public static function requireUploadable(id:String, bundled:Bool):Void {
        if (!bundled && bundledThemeId(id)) {
            throw new Exception("Bundled themes are updated with HaxePress. Fork the theme to change it.");
        }
    }

    /** Installs every bundled theme, or replaces it when the shipped archive changed. **/
    static function ensureThemes():Void {
        var disk = Storage.disk("public");
        for (slug in themes) {
            var id = 'theme-${slug}';
            var path = archive(slug);
            if (!disk.fileExists(path)) {
                continue;
            }
            // Read without the content cache: a restart must not rewrite cached entries.
            var installed = InstalledPackage.query.select(["author"])
                .where("id", id)
                .limit(1)
                .first();
            if (installed != null && !shippedAuthor(installed.author)) {
                trace('A different theme occupies the bundled theme ID ${id}.');
                continue;
            }
            refresh(id, "theme", disk.getBytes(path), installed != null);
        }
        if (!InstalledPackage.query.where("kind", "theme").where("enabled", 1).exists()) {
            PackageManager.enable(BuiltInTheme.ID, 0, "System");
        }
    }

    /** Replaces the installed example plugin when the shipped archive changed. **/
    static function upgradePlugins():Void {
        var disk = Storage.disk("public");
        for (bundle in plugins) {
            var id = 'plugin-${bundle.slug}';
            var path = archive(bundle.slug);
            if (!disk.fileExists(path)) {
                continue;
            }
            var installed = InstalledPackage.query.select(["manifest"])
                .where("id", id)
                .limit(1)
                .first();
            if (installed == null) {
                continue;
            }
            if (!shipped(PackageManifest.parse(installed.manifest), bundle.entrypoint)) {
                continue;
            }
            refresh(id, "plugin", disk.getBytes(path), true);
        }
    }

    /** The archive of a bundled package on the public disk, built with this version. **/
    static function archive(slug:String):String {
        return 'packages/${slug}-${CmsVersion.version}.zip';
    }

    /** The setting that holds the digest of the archive a bundled package was installed from. **/
    static function marker(id:String):String {
        return 'cms_example_${id}';
    }

    /**
        Installs a bundled package from its archive unless it already matches
        it. On failure the digest stays unrecorded, so the next start tries again.
    **/
    static function refresh(id:String, kind:String, bytes:Bytes, installed:Bool):Void {
        var digest = Sha256.make(bytes).toHex();
        if (installed && Setting.query.where("key", marker(id)).where("value", digest).exists()) {
            return;
        }
        try {
            var inspection = PackageManager.stage(bytes, kind, 0, true);
            PackageManager.install(inspection.key, kind, 0, "System", installed, true);
            Setting.query.upsert(["key" => marker(id), "value" => digest], ["key"], ["value"]);
        } catch (error:Dynamic) {
            trace('Bundled package ${id} could not be installed: ${Std.string(error)}');
        }
    }

    /**
        Themes built for the former browser renderer cannot run. Any such
        theme is removed, and the built-in theme takes over when it was the
        active one; bundled themes are replaced with their Wellout builds by
        `ensureThemes` instead. Runs on every start, so a restored backup is
        cleaned too.
    **/
    static function retireRendererThemes():Void {
        var disk = Storage.disk("public");
        var legacy = InstalledPackage.query.select(["id", "slug", "author", "manifest", "enabled"])
            .where("kind", "theme")
            .whereLike("manifest", '%"renderer"%')
            .limit(64)
            .get();
        for (theme in legacy) {
            var manifest = PackageManifest.parse(theme.manifest);
            if (!manifest.legacyRenderer) {
                continue;
            }
            var bundled = isBundledTheme(theme.id, theme.author);
            if (bundled && disk.fileExists(archive(theme.slug))) {
                // Replaced with its Wellout build, keeping its activation.
                continue;
            }
            try {
                if (theme.enabled == 1) {
                    PackageManager.enable(BuiltInTheme.ID, 0, "System");
                }
                if (bundled) {
                    continue;
                }
                PackageManager.uninstall(theme.id, 0, "System");
                trace('Removed theme ${theme.id}: it was built for the former browser renderer.');
            } catch (error:Dynamic) {
                trace('Theme ${theme.id} could not be removed: ${Std.string(error)}');
            }
        }
    }

    static function bundledThemeId(id:String):Bool {
        var prefix = "theme-";
        return StringTools.startsWith(id, prefix) && themes.contains(id.substr(prefix.length));
    }

    static function shippedAuthor(author:String):Bool {
        return ["Fieldnotes", "HxWell CMS", "HaxePress"].contains(author);
    }

    /** Whether an installed package is one of the examples shipped with HaxePress. **/
    static function shipped(manifest:ManifestData, entrypoint:String):Bool {
        return shippedAuthor(manifest.author) && manifest.entrypoint == entrypoint;
    }
}
