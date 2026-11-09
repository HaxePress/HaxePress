package hx.press.i18n;

import hx.press.i18n.TranslationSync.SyncedText;
import hx.press.model.InstalledPackage;
import hx.press.packages.BuiltInTheme;
import hx.press.packages.PackageManifest;
import hx.press.packages.PackageManifest.ManifestData;
import hx.press.view.PluginViews;
import hx.press.view.ThemeViews;
import hx.press.view.ViewEngine;
import hx.well.facades.Storage;

typedef PackageTexts = {
    var language:String;
    var texts:Array<SyncedText>;
}

/**
    The texts the CMS, the built-in theme and installed packages ship: their
    catalogue keys, the literal keys their templates translate and the
    labels of their manifests.
**/
class TranslationSources {
    /** Pages visitors see; every template they call is part of the public site. **/
    static final publicPages = ["Home", "ContentIndex", "ContentDetail", "Page", "About", "NotFound"];

    /** Server messages of public pages that no template names. **/
    static final publicPrefixes = ["month.", "date."];

    /**
        The core catalogue keys used on public pages. Every other CMS text
        belongs to the administration, which a site translates only when
        its members use the administration in that language.
    **/
    static function publicKeys():Map<String, Bool> {
        var keys:Map<String, Bool> = [];
        var visited:Map<String, Bool> = [];
        var queue = publicPages.copy();
        while (queue.length > 0) {
            var name = queue.pop();
            if (visited.exists(name) || !ViewEngine.library.has(name)) {
                continue;
            }
            visited.set(name, true);
            var result = ViewEngine.library.check(name);
            if (result == null || result.value == null) {
                continue;
            }
            var components:Array<String> = [];
            for (use in TemplateKeys.collect(result.value, components)) {
                if (use.namespace == null || use.namespace == "cms") {
                    keys.set(use.key, true);
                }
            }
            for (component in components) {
                if (!StringTools.startsWith(component, "Admin")) {
                    queue.push(component);
                }
            }
        }
        return keys;
    }

    /** The core keys the templates of installed themes translate. **/
    static function themeKeys():Map<String, Bool> {
        var keys:Map<String, Bool> = [];
        var themes = InstalledPackage.query.select(["id", "directory", "manifest"])
            .where("kind", "theme")
            .orderBy("id")
            .limit(100)
            .get();
        var disk = Storage.disk("extensions");
        for (theme in themes) {
            var manifest = PackageManifest.parse(theme.manifest);
            if (manifest.views == "") {
                continue;
            }
            try {
                var folder = 'installed/${theme.directory}/${manifest.views}';
                for (use in ThemeViews.translationKeys(disk, folder)) {
                    if (use.namespace == null || use.namespace == "cms") {
                        keys.set(use.key, true);
                    }
                }
            } catch (error:Dynamic) {
                trace('The templates of ${theme.id} could not be read for translation: ${Std.string(error)}');
            }
        }
        return keys;
    }

    /** The core texts a theme's templates show, which visitors therefore see. **/
    public static function coreKeysOf(id:String):Array<String> {
        var record = InstalledPackage.query.select(["kind", "directory", "manifest"])
            .where("id", id)
            .limit(1)
            .first();
        if (record == null || record.kind != "theme") {
            return [];
        }
        var manifest = PackageManifest.parse(record.manifest);
        if (manifest.views == "") {
            return [];
        }
        var core = I18n.coreCatalogues().get(I18n.FALLBACK);
        var folder = 'installed/${record.directory}/${manifest.views}';
        return [
            for (use in ThemeViews.translationKeys(Storage.disk("extensions"), folder))
                if ((use.namespace == null || use.namespace == "cms") && core.exists(use.key))
                    use.key
        ];
    }

    static function sortedKeys(messages:Map<String, Dynamic>):Array<String> {
        var keys = [for (key in messages.keys()) key];
        keys.sort(Reflect.compare);
        return keys;
    }

    static function shippedFor(key:String, catalogues:Map<String, Map<String, Dynamic>>,
            source:String):Map<String, Dynamic> {
        var shipped:Map<String, Dynamic> = [];
        for (code => messages in catalogues) {
            if (code != source && messages.exists(key)) {
                shipped.set(code, messages.get(key));
            }
        }
        return shipped;
    }

    public static function core():Array<SyncedText> {
        var catalogues = I18n.coreCatalogues();
        var english = catalogues.get(I18n.FALLBACK);
        var visible = publicKeys();
        for (key in themeKeys().keys()) {
            visible.set(key, true);
        }
        var texts:Array<SyncedText> = [];
        for (key in sortedKeys(english)) {
            var site = visible.exists(key)
                || Lambda.exists(publicPrefixes, prefix -> StringTools.startsWith(key, prefix));
            texts.push({
                key: key,
                source: english.get(key),
                origin: "catalogue",
                audience: site ? "site" : "admin",
                shipped: shippedFor(key, catalogues, I18n.FALLBACK)
            });
        }
        return texts;
    }

    public static function builtInTheme():Array<SyncedText> {
        var catalogues:Map<String, Map<String, Dynamic>> = [];
        for (choice in I18n.locales) {
            var source = BuiltInTheme.translations(choice.code);
            if (source != null) {
                catalogues.set(choice.code, TranslationCatalogue.parseTrusted(source));
            }
        }
        var english = catalogues.get(I18n.FALLBACK) ?? new Map<String, Dynamic>();
        return [
            for (key in sortedKeys(english))
                {
                    key: key,
                    source: english.get(key),
                    origin: "catalogue",
                    audience: "site",
                    shipped: shippedFor(key, catalogues, I18n.FALLBACK)
                }
        ];
    }

    /** The texts of an installed theme or plugin, or null when it is not installed. **/
    public static function forPackage(id:String):Null<PackageTexts> {
        if (BuiltInTheme.isBuiltIn(id)) {
            return {language: I18n.FALLBACK, texts: builtInTheme()};
        }
        var record = InstalledPackage.query.select(["id", "kind", "directory", "manifest"])
            .where("id", id)
            .limit(1)
            .first();
        if (record == null) {
            return null;
        }
        var manifest = PackageManifest.parse(record.manifest);
        var disk = Storage.disk("extensions");
        var root = 'installed/${record.directory}';
        var catalogues:Map<String, Map<String, Dynamic>> = [];
        for (code => path in manifest.translations) {
            var filename = '${root}/${path}';
            if (disk.fileExists(filename) && disk.size(filename) <= TranslationCatalogue.MAX_BYTES) {
                catalogues.set(code, TranslationCatalogue.parse(disk.get(filename)));
            }
        }
        var language = manifest.sourceLanguage;
        var source = catalogues.get(language) ?? new Map<String, Dynamic>();
        var core = I18n.coreCatalogues().get(I18n.FALLBACK);
        var texts:Array<SyncedText> = [];
        var listed:Map<String, Bool> = [];
        var add = (key:String, message:Dynamic, origin:String, audience:String) -> {
            if (key == "" || listed.exists(key)) {
                return;
            }
            listed.set(key, true);
            texts.push({
                key: key,
                source: message,
                origin: origin,
                audience: audience,
                shipped: shippedFor(key, catalogues, language)
            });
        };
        for (key in sortedKeys(source)) {
            add(key, source.get(key), "catalogue", "site");
        }
        // Keys only other catalogues translate still have their key as the source text.
        for (code => messages in catalogues) {
            for (key in sortedKeys(messages)) {
                add(key, key, "catalogue", "site");
            }
        }
        for (label in manifestLabels(manifest)) {
            if (!core.exists(label)) {
                add(label, label, "manifest", "admin");
            }
        }
        if (manifest.views != "") {
            var folder = '${root}/${manifest.views}';
            var keys = record.kind == "theme" ? ThemeViews.translationKeys(disk,
                folder) : PluginViews.translationKeys(disk, folder);
            for (use in keys) {
                var own = use.namespace == null || use.namespace == id;
                if (own && !core.exists(use.key)) {
                    add(use.key, use.key, "template", "site");
                }
            }
        }
        return {language: language, texts: texts};
    }

    /** Texts of a manifest the administration shows, which packages translate by their wording. **/
    static function manifestLabels(manifest:ManifestData):Array<String> {
        var labels = [manifest.name, manifest.description];
        for (field in manifest.fields) {
            labels.push(field.label);
            labels.push(field.help);
            for (option in field.options) {
                labels.push(option.label);
            }
        }
        for (template in manifest.templates) {
            labels.push(template.label);
        }
        for (region in manifest.navigation) {
            labels.push(region.name);
        }
        return labels.filter(label -> label != null && StringTools.trim(label) != "");
    }
}
