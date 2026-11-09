package hx.press.i18n;

import hx.press.ContentCache;
import hx.press.i18n.TranslationData.TranslationPackageRecord;
import hx.press.packages.PackageManifest;
import hx.press.packages.BuiltInTheme;
import haxe.Resource;
import hx.well.facades.Storage;
import hx.well.http.RequestStatic;
#if php
import haxe.crypto.Sha256;
import hx.press.BuildIdentity;
import hx.press.PhpDataFile;
import php.Global;
import php.Lib;
import php.NativeAssocArray;
import php.Syntax;
#end
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
        #if php
        return storedCore();
        #else
        return parseCore();
        #end
    }

    static function parseCore():Map<String, Map<String, Dynamic>> {
        var catalogues:Map<String, Map<String, Dynamic>> = [];
        for (choice in locales) {
            var source = Resource.getString('lang.${choice.code}');
            var messages = source == null ? new Map() : TranslationCatalogue.parseTrusted(source);
            catalogues.set(choice.code, messages);
        }
        return catalogues;
    }

    #if php
    /**
        PHP starts the application for each request. The core catalogues are
        part of the build, so they are parsed once per build and then read
        from a data file: a few plural forms become objects again, and every
        other message stays the stored native string.
    **/
    static function storedCore():Map<String, Map<String, Dynamic>> {
        var path = 'cache/i18n/${Sha256.encode(BuildIdentity.id).substr(0, 40)}.php';
        var stored:Dynamic = PhpDataFile.read(Storage.disk("local").path(path));
        if (stored != null) {
            var catalogues:Map<String, Map<String, Dynamic>> = [];
            Syntax.foreach(stored, (locale:String, messages:NativeAssocArray<Dynamic>) -> {
                Syntax.foreach(messages, (key:String, message:Dynamic) -> {
                    if (Global.is_array(message)) {
                        messages[key] = Lib.objectOfAssociativeArray(message);
                    }
                });
                catalogues.set(locale, Lib.hashOfAssociativeArray(messages));
            });
            return catalogues;
        }
        var catalogues = parseCore();
        var exported = new NativeAssocArray<NativeAssocArray<Dynamic>>();
        for (locale => messages in catalogues) {
            var native = new NativeAssocArray<Dynamic>();
            for (key => message in messages) {
                // A plural form is an object, which the data file keeps as an array.
                if (Std.isOfType(message, String)) {
                    native[key] = message;
                } else {
                    native[key] = Lib.associativeArrayOfObject(message);
                }
            }
            exported[locale] = native;
        }
        PhpDataFile.write(path, exported, "Core translation catalogues of this build");
        return catalogues;
    }
    #end

    /** The core catalogues as shipped, by locale; callers must not change them. **/
    public static function coreCatalogues():Map<String, Map<String, Dynamic>> {
        return core;
    }

    public static function supported(locale:String):Bool {
        for (choice in locales) {
            if (choice.code == locale) {
                return true;
            }
        }
        return false;
    }

    /** The site's default language, which pages use when a request names none. **/
    public static function defaultLocale():String {
        return Languages.defaultCode();
    }

    /**
        Whether pages can be shown in a locale: it has a core catalogue or is
        one of the site's languages, whose missing messages fall back to
        English.
    **/
    public static function known(locale:Null<String>):Bool {
        return locale != null && (supported(locale) || Languages.exists(locale));
    }

    public static function locale():String {
        var request = RequestStatic.request();
        if (request != null) {
            var selected:String = request.getAttribute("hx.press.locale");
            if (known(selected)) {
                return selected;
            }
        }
        return defaultLocale();
    }

    /**
        Whether members can choose a locale for the administration: one with a
        core catalogue, or a site language whose missing messages fall back
        to English.
    **/
    public static function adminLocale(locale:Null<String>):Bool {
        return known(locale);
    }

    /** The interface languages members can choose. **/
    public static function adminLocales():Array<LocaleChoice> {
        var choices = locales.copy();
        for (language in Languages.all()) {
            if (!supported(language.code)) {
                choices.push({
                    code: language.code,
                    name: language.name,
                    direction: language.direction
                });
            }
        }
        return choices;
    }

    /** The first core locale an `Accept-Language` header names, or English. **/
    public static function preferredAdminLocale(header:Null<String>):String {
        if (header == null || header.length > 500) {
            return FALLBACK;
        }
        for (part in header.split(",")) {
            var tag = StringTools.trim(part.split(";")[0]);
            if (supported(tag)) {
                return tag;
            }
            if (tag.length > 0 && supported(base(tag).toLowerCase())) {
                return base(tag).toLowerCase();
            }
        }
        return FALLBACK;
    }

    /** The language part of a locale, such as `pt` for `pt-BR`. **/
    static function base(locale:String):String {
        var separator = locale.indexOf("-");
        return separator < 0 ? locale : locale.substr(0, separator);
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
        A package's messages in a locale, merged once per installed
        generation and revision of the site's translations: a new version
        installs into a new directory. The map is shared; callers must not
        change it.
    **/
    static function packageMessages(record:TranslationPackageRecord,
            selected:String):Map<String, Dynamic> {
        // The extensions revision changes when catalogues are cached anew, such as after clearing the cache.
        var revisions = '${ContentCache.revision("extensions")}:${ContentCache.revision("translations")}';
        var key = '${revisions}:${record.id}:${record.directory}:${selected}';
        var known = merged(key);
        if (known != null) {
            return known;
        }
        var source = BuiltInTheme.isBuiltIn(record.id) ? FALLBACK : PackageManifest.stored(record.manifest)
            .sourceLanguage;
        return remember(key,
            layered(record.id, source, selected, code -> packageCatalogue(record, code)));
    }

    /**
        The messages of a namespace in `selected`, each layer over the one
        before: English, the source catalogue, the site's changes to the
        source wording, the catalogue of the locale (or its base language)
        and the site's translations into it.
    **/
    static function layered(namespace:String, source:String, selected:String,
            catalogue:String->Map<String, Dynamic>):Map<String, Dynamic> {
        var messages:Map<String, Dynamic> = [];
        var add = (layer:Map<String, Dynamic>) -> {
            for (key => value in layer) {
                messages.set(key, value);
            }
        };
        if (source != FALLBACK) {
            add(catalogue(FALLBACK));
        }
        add(catalogue(source));
        add(TranslationOverrides.forLanguage(namespace, source));
        if (selected != source) {
            var own = catalogue(selected);
            if (Lambda.empty(own) && base(selected) != selected) {
                own = catalogue(base(selected));
            }
            add(own);
            add(TranslationOverrides.forLanguage(namespace, selected));
        }
        return messages;
    }

    static function merged(key:String):Null<Map<String, Dynamic>> {
        mergedLock.acquire();
        var known = mergedPackages.get(key);
        mergedLock.release();
        return known;
    }

    static function remember(key:String, messages:Map<String, Dynamic>):Map<String, Dynamic> {
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
        var selected = known(selectedLocale) ? selectedLocale : locale();
        var message:Dynamic = null;
        if (namespace != "cms") {
            var record = TranslationData.one(namespace);
            if (record != null) {
                message = packageMessages(record, selected).get(key);
            }
        }
        if (message == null) {
            message = coreMessages(selected).get(key);
        }
        return TranslationCatalogue.format(message, key, parameters);
    }

    /**
        The CMS messages of a locale with the site's translations, merged once
        per revision of the translations; callers must not change the map.
    **/
    public static function coreMessages(selected:String):Map<String, Dynamic> {
        var key = 'cms:${ContentCache.revision("translations")}:${selected}';
        var known = merged(key);
        if (known != null) {
            return known;
        }
        return remember(key,
            layered("cms", FALLBACK, selected,
                code -> core.get(code) ?? new Map<String, Dynamic>()));
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
        return Languages.direction(selected);
    }

    public static function props(?preview:TranslationPackageRecord):TranslationProps {
        var selected = locale();
        var catalogues:Map<String, Map<String, Dynamic>> = [];
        catalogues.set("cms", coreMessages(selected));
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
            locales: adminLocales(),
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
