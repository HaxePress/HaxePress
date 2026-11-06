package hx.press.i18n;

import hx.press.ContentCache;
import hx.press.SiteSettingsStore;
import hx.press.i18n.TranslationData.TranslationPackageRecord;
import hx.press.packages.PackageManifest;
import hx.press.packages.BuiltInTheme;
import haxe.Resource;
import hx.well.facades.Storage;
import hx.well.http.RequestStatic;

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
            var editor = Resource.getString('lang.editor.${choice.code}');
            if (editor != null) {
                messages = merge(messages, TranslationCatalogue.parse(editor));
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

    static function packageMessages(record:TranslationPackageRecord,
            selected:String):Map<String, Dynamic> {
        var fallback = packageCatalogue(record, FALLBACK);
        return selected == FALLBACK ? fallback : merge(fallback,
            packageCatalogue(record, selected));
    }

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
        var direction = "ltr";
        for (choice in locales) {
            if (choice.code == selected) {
                direction = choice.direction;
            }
        }
        return {
            locale: selected,
            direction: direction,
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
