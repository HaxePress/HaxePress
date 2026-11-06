package hx.press.packages;

import hx.press.packages.PackageData.PackageRecord;
import hx.press.themes.ThemeDesignData;

class ThemeData {
    public static function active():Dynamic {
        return info(PackageData.activeTheme());
    }

    /** `draft` shows a builder theme's saved draft instead of its published design. **/
    public static function info(record:Null<PackageRecord>, preview:Bool = false,
            draft:Bool = false):Dynamic {
        if (record == null) {
            return {
                id: BuiltInTheme.ID,
                built_in: true,
                name: "Simple",
                slug: "simple",
                layout: "simple",
                stylesheet: "",
                module: "",
                assetBase: "",
                settings: new Map<String, String>(),
                templates: [],
                navigation: ["header", "footer"],
                preview: false
            };
        }
        var manifest = PackageManifest.stored(record.manifest);
        var builtIn = BuiltInTheme.isBuiltIn(record.id);
        return {
            id: record.id,
            built_in: builtIn,
            name: record.name,
            slug: record.slug,
            layout: manifest.layout,
            stylesheet: builtIn ? "" : PackageStorage.assetUrl(record, manifest.stylesheet,
                preview),
            module: builtIn ? "" : PackageStorage.assetUrl(record, manifest.module, preview),
            assetBase: builtIn ? "" : PackageStorage.assetBase(record, preview),
            settings: PackageSettings.values(manifest, record.settings, false),
            templates: manifest.templates,
            navigation: ["header", "footer"].concat([
                for (region in manifest.navigation)
                    if (region.key != "header" && region.key != "footer") region.key
            ]),
            preview: preview,
            design: manifest.layout != "builder" ? null : draft ? ThemeDesignData.draft(record.id) : ThemeDesignData.published(record.id,
                preview)
        };
    }
}
