package hx.press.packages;

import hx.press.packages.PackageData.PackageRecord;
import hx.press.themes.ThemeDesignData;

class ThemeData {
    public static function active():Dynamic {
        return info(PackageData.activeTheme());
    }

    public static function info(record:Null<PackageRecord>, preview:Bool = false):Dynamic {
        if (record == null) {
            return {
                id: BuiltInTheme.ID,
                built_in: true,
                name: "Simple",
                slug: "simple",
                layout: "simple",
                stylesheet: "",
                module: "",
                renderer: "",
                assetBase: "",
                settings: new Map<String, String>(),
                templates: [],
                navigation: ["header", "footer"],
                preview: false
            };
        }
        var manifest = PackageManifest.parse(record.manifest);
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
            renderer: builtIn ? "" : PackageStorage.assetUrl(record, manifest.renderer, preview),
            assetBase: builtIn ? "" : PackageStorage.assetBase(record, preview),
            settings: PackageSettings.values(manifest, record.settings, false),
            templates: manifest.templates,
            navigation: ["header", "footer"].concat([
                for (region in manifest.navigation)
                    if (region.key != "header" && region.key != "footer") region.key
            ]),
            preview: preview,
            design: manifest.layout == "builder" ? ThemeDesignData.published(record.id,
                preview) : null
        };
    }
}
