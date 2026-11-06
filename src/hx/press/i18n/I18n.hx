package hx.press.i18n;

import hx.press.ContentCache;
import hx.press.SiteSettingsStore;
import hx.press.i18n.TranslationData.TranslationPackageRecord;
import hx.press.packages.PackageManifest;
import hx.press.packages.BuiltInTheme;
import haxe.Resource;
import hx.well.facades.Storage;
import hx.well.http.RequestStatic;
#if (target.threaded)
import sys.thread.Mutex;
#else
import hx.well.thread.FakeMutex as Mutex;
#end

typedef LocaleChoice = {
    var code:String;
    var name:String;
    var direction:String;
}

typedef TranslationProps = {
    var locale:String;
    var direction:String;
    var fallbackLocale:String;
    var locales:Array<LocaleChoice>;
    var catalogues:Map<String, Map<String, Dynamic>>;
}

class I18n {
    public static inline var FALLBACK = "en";
    public static final locales:Array<LocaleChoice> = [
        {code: "en", name: "English", direction: "ltr"},
        {code: "tr", name: "Türkçe", direction: "ltr"}
    ];
    static final core:Map<String, Map<String, Dynamic>> = loadCore();

    static function loadCore():Map<String, Map<String, Dynamic>> {
        var catalogues:Map<String, Map<String, Dynamic>> = [];
        for (choice in locales) {
            var source = Resource.getString('lang.${choice.code}');
            var messages = source == null ? new Map() : TranslationCatalogue.parse(source);
            for (section in ["editor", "packages"]) {
                var additional = Resource.getString('lang.${section}.${choice.code}');
                if (additional != null) {
                    for (key => value in TranslationCatalogue.parse(additional)) {
                        messages.set(key, value);
                    }
                }
            }
            catalogues.set(choice.code, messages);
        }
        return catalogues;
    }

    public static function supported(locale:String):Bool {
        for (choice in locales) {
            if (choice.code == locale) {
                return true;
            }
        }
        return false;
    }

    public static function defaultLocale():String {
        var configured = SiteSettingsStore.settings().get("locale");
        return supported(configured) ? configured : FALLBACK;
    }

    public static function locale():String {
        var request = RequestStatic.request();
        if (request != null) {
            var selected:String = request.getAttribute("hx.press.locale");
            if (supported(selected)) {
                return selected;
            }
        }
        return defaultLocale();
    }

    static function merge(fallback:Map<String, Dynamic>,
            selected:Map<String, Dynamic>):Map<String, Dynamic> {
        var messages = fallback.copy();
        for (key => value in selected) {
            messages.set(key, value);
        }
        return messages;
    }

    static function packageCatalogue(record:TranslationPackageRecord,
            locale:String):Map<String, Dynamic> {
        return ContentCache.remember("extensions", "translations",
            [record.id, record.directory, locale], () -> {
                if (BuiltInTheme.isBuiltIn(record.id)) {
                    var source = BuiltInTheme.translations(locale);
                    return source == null ? new Map() : TranslationCatalogue.parse(source);
                }
                var manifest = PackageManifest.parse(record.manifest);
                var path = manifest.translations.get(locale);
                if (path == null) {
                    return new Map();
                }
                var disk = Storage.disk("extensions");
                var filename = 'installed/${record.directory}/${path}';
                if (!disk.fileExists(filename)
                    || disk.size(filename) > TranslationCatalogue.MAX_BYTES) {
                    return new Map();
                }
                return TranslationCatalogue.parse(disk.get(filename));
            });
    }

    /**
        A package's catalogue for a locale over its fallback, merged once per
        installed generation and cache revision: a new version installs into a
        new directory. The map is shared; callers must not change it.
    **/
    static function packageMessages(record:TranslationPackageRecord,
            selected:String):Map<String, Dynamic> {
        // The extensions revision changes when catalogues are cached anew, such as after clearing the cache.
        var revision = ContentCache.revision("extensions");
        var key = '${revision}:${record.id}:${record.directory}:${selected}';
        mergedLock.acquire();
        var known = mergedPackages.get(key);
        mergedLock.release();
        if (known != null) {
            return known;
        }
        var fallback = packageCatalogue(record, FALLBACK);
        var messages = selected == FALLBACK ? fallback : merge(fallback,
            packageCatalogue(record, selected));
        mergedLock.acquire();
        if (!mergedPackages.exists(key)) {
            mergedOrder.push(key);
            if (mergedOrder.length > MAX_MERGED_PACKAGES) {
                mergedPackages.remove(mergedOrder.shift());
            }
        }
        mergedPackages.set(key, messages);
        mergedLock.release();
        return messages;
    }

    static inline var MAX_MERGED_PACKAGES = 128;
    static final mergedPackages:Map<String, Map<String, Dynamic>> = [];
    static final mergedOrder:Array<String> = [];
    static final mergedLock = new Mutex();

    public static function t(key:String, ?parameters:Map<String, Dynamic>,
            namespace:String = "cms", ?selectedLocale:String):String {
        var selected = supported(selectedLocale) ? selectedLocale : locale();
        var message:Dynamic = null;
        if (namespace != "cms") {
            var record = TranslationData.one(namespace);
            if (record != null) {
                message = packageMessages(record, selected).get(key);
            }
        }
        if (message == null) {
            message = core.get(selected).get(key);
        }
        if (message == null) {
            message = core.get(FALLBACK).get(key);
        }
        return TranslationCatalogue.format(message, key, parameters);
    }

    static final mergedCore:Map<String, Map<String, Dynamic>> = [
        for (choice in locales)
            choice.code => merge(core.get(FALLBACK), core.get(choice.code))
    ];

    /** The CMS catalogue of a locale over the fallback, built once; callers must not change it. **/
    public static function coreMessages(selected:String):Map<String, Dynamic> {
        var messages = mergedCore.get(selected);
        return messages == null ? mergedCore.get(FALLBACK) : messages;
    }

    /** The catalogue of a theme or plugin over its fallback, or null when it has none. **/
    public static function namespaceMessages(namespace:String,
            selected:String):Null<Map<String, Dynamic>> {
        var record = TranslationData.one(namespace);
        return record == null ? null : packageMessages(record, selected);
    }

    /**
        The catalogue of an installed theme or plugin whether or not it is
        enabled, for administration pages such as previews and package
        settings. Public pages use `namespaceMessages`, which reads only
        enabled packages.
    **/
    public static function installedMessages(namespace:String,
            selected:String):Null<Map<String, Dynamic>> {
        var enabled = namespaceMessages(namespace, selected);
        if (enabled != null) {
            return enabled;
        }
        var records = TranslationData.byIds([namespace]);
        return records.length == 0 ? null : packageMessages(records[0], selected);
    }

    /** `t` for administration pages: an installed package's message, else the CMS one. **/
    public static function installedT(key:String, ?parameters:Map<String, Dynamic>,
            namespace:String = "cms"):String {
        var selected = locale();
        var own = namespace == "cms" ? null : installedMessages(namespace, selected);
        var message:Dynamic = own == null ? null : own.get(key);
        return TranslationCatalogue.format(message ?? coreMessages(selected).get(key), key,
            parameters);
    }

    /** The writing direction of a locale: `ltr` or `rtl`. **/
    public static function direction(selected:String):String {
        for (choice in locales) {
            if (choice.code == selected) {
                return choice.direction;
            }
        }
        return "ltr";
    }

    public static function props(?preview:TranslationPackageRecord):TranslationProps {
        var selected = locale();
        var catalogues:Map<String, Map<String, Dynamic>> = [];
        catalogues.set("cms", merge(core.get(FALLBACK), core.get(selected)));
        for (record in TranslationData.active()) {
            catalogues.set(record.id, packageMessages(record, selected));
        }
        if (preview != null) {
            catalogues.set(preview.id, packageMessages(preview, selected));
        }
        return {
            locale: selected,
            direction: direction(selected),
            fallbackLocale: FALLBACK,
            locales: locales,
            catalogues: catalogues
        };
    }

    public static function includePackages(data:TranslationProps,
            ids:Array<String>):TranslationProps {
        for (record in TranslationData.byIds(ids)) {
            data.catalogues.set(record.id, packageMessages(record, data.locale));
        }
        return data;
    }
}
