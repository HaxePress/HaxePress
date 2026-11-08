package hx.press.packages;

import haxe.Exception;
import haxe.Json;
import hx.press.CmsVersion;
import hx.press.validation.Slug;

typedef SettingOption = {
    var value:String;
    var label:String;
}

typedef PackageField = {
    var key:String;
    var label:String;
    var kind:String;
    var help:String;
    var defaultValue:String;
    var required:Bool;
    var minimum:Float;
    var maximum:Float;
    var options:Array<SettingOption>;
}

typedef ManifestData = {
    var apiVersion:Int;
    var cmsVersion:String;
    var kind:String;
    var pluginId:Null<String>;
    var slug:String;
    var name:String;
    var version:String;
    var description:String;
    var author:String;
    var hooks:Array<String>;
    var fields:Array<PackageField>;
    var module:String;

    /**
        Whether the package was built for the former browser renderer
        (`assets.renderer`). Such themes are rejected on installation and
        removed or replaced on startup (`PackageBundles`).
    **/
    var legacyRenderer:Bool;

    /** The folder of the package's Wellout templates (`*.well.html`), relative to the package root. **/
    var views:String;

    /**
        Host locks a plugin needs while its routes and scheduled tasks run:
        `packages` keeps installed packages unchanged, `media` keeps media
        files unchanged.
    **/
    var locks:Array<String>;

    /**
        The catalogue keys the frontend module translates with `t`. Pages send
        the module only these messages of the package's catalogue.
    **/
    var messages:Array<String>;

    var stylesheet:String;
    var serverJar:String;
    var serverCppia:String;
    var serverPhp:String;
    var entrypoint:String;
    var layout:String;
    var designFile:String;
    var mediaFile:String;
    var mediaPrefix:String;
    var translations:Map<String, String>;
    var templates:Array<{name:String, label:String, scope:String}>;
    var navigation:Array<{key:String, name:String, maxLinks:Int}>;
}

class PackageManifest {
    public static inline var FILENAME = "cms-package.json";
    static inline var MAX_STORED = 64;
    static final storedManifests:Map<String, ManifestData> = [];
    static final storedOrder:Array<String> = [];
    #if (target.threaded)
    static final storedLock = new sys.thread.Mutex();
    #end
    public static inline var RENDERER_UNSUPPORTED = "Browser theme renderers are no longer supported. Package the theme's pages as Wellout templates in a views folder.";

    public static function validPluginId(id:Null<String>):Bool {
        return id != null
            && ~/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}(?![\s\S])/.match(id);
    }

    public static final events = [
        "site.shared",
        "site.assets",
        "content.render",
        "content.saving",
        "content.saved",
        "dashboard.widgets",
        "ui.navigation",
        "i18n.catalogues",
        "installation"
    ];

    /** The hooks the host serves itself, the only ones a plugin without a server module uses. **/
    public static final hostEvents = ["site.assets", "i18n.catalogues"];

    /** The host locks a plugin can hold while it runs, in the order they are acquired. **/
    public static final lockNames = ["packages", "media"];

    public static function text(object:Dynamic, field:String, maximum:Int,
            required:Bool = false):String {
        var value:Dynamic = object == null ? null : Reflect.field(object, field);
        if (value == null && !required) {
            return "";
        }
        if (!Std.isOfType(value, String)) {
            throw new Exception('The package field ${field} must contain text.');
        }
        var result = StringTools.trim(value);
        if (result.length > maximum || (required && result == "")) {
            throw new Exception('The package field ${field} has an invalid length.');
        }
        return result;
    }

    public static function safePath(path:String):Bool {
        if (path == "" || path.length > 240 || !~/^[A-Za-z0-9_.\/-]+(?![\s\S])/.match(path)) {
            return false;
        }
        var segments = path.split("/");
        if (segments.length > 8) {
            return false;
        }
        for (segment in segments) {
            if (segment == "" || StringTools.startsWith(segment, ".")) {
                return false;
            }
        }
        return true;
    }

    /**
        Reads the manifest of an installed package. A hook a later version of
        the host no longer offers is left out, so the package keeps working
        without it. Uploaded packages are read with `parseUpload`.
    **/
    public static function parse(source:String):ManifestData {
        return read(source, false);
    }

    /** Reads an uploaded package's manifest, which must name only the hooks this host offers. **/
    public static function parseUpload(source:String):ManifestData {
        return read(source, true);
    }

    static function read(source:String, uploaded:Bool):ManifestData {
        if (source.length > 65536) {
            throw new Exception("The package manifest is too large.");
        }
        var input:Dynamic;
        try {
            input = Json.parse(source);
        } catch (error:Dynamic) {
            throw new Exception("The package manifest must contain valid JSON.");
        }
        if (input == null
            || !Std.isOfType(input.apiVersion, Int)
            || (input.apiVersion < 1 || input.apiVersion > CmsVersion.pluginApiVersion)) {
            throw new Exception("This package requires an unsupported CMS API version.");
        }
        var kind = text(input, "kind", 10, true);
        var identity = text(input, "pluginId", 36);
        if (identity != "" && (kind != "plugin" || !validPluginId(identity))) {
            throw new Exception("Use a stable lowercase UUID as the plugin ID.");
        }
        var slug = text(input, "slug", 64, true);
        var version = text(input, "version", 40, true);
        if (!["plugin", "theme"].contains(kind) || !Slug.valid(slug)) {
            throw new Exception("Choose a valid plugin or theme package.");
        }
        if (!~/^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?(?![\s\S])/.match(version)) {
            throw new Exception("Package versions must use the major.minor.patch format.");
        }
        var hooks:Array<String> = [];
        if (input.hooks != null) {
            if (!Std.isOfType(input.hooks, Array)) {
                throw new Exception("Package hooks must be a list.");
            }
            var requested:Array<Dynamic> = input.hooks;
            if (requested.length > 16) {
                throw new Exception("A package can subscribe to at most 16 hooks.");
            }
            for (event in requested) {
                if (!Std.isOfType(event, String)) {
                    throw new Exception("The package subscribes to an unsupported hook.");
                }
                if (!events.contains(event)) {
                    if (uploaded) {
                        throw new Exception("The package subscribes to an unsupported hook.");
                    }
                    continue;
                }
                if (!hooks.contains(event)) {
                    hooks.push(event);
                }
            }
        }
        var assets = input.assets;
        var module = text(assets, "module", 240);
        var legacyRenderer = assets != null && Reflect.field(assets, "renderer") != null;
        var views = text(assets, "views", 240);
        if (views != "" && (!safePath(views) || views.indexOf(".") >= 0)) {
            throw new Exception("Package views must reference a folder of Wellout templates.");
        }
        var locks = lockList(input.locks);
        if (locks.length > 0 && kind != "plugin") {
            throw new Exception("Only plugins can hold host locks.");
        }
        var stylesheet = text(assets, "stylesheet", 240);
        var messages = messageKeys(assets == null ? null : assets.messages);
        if (messages.length > 0 && module == "") {
            throw new Exception("Only a package with a frontend module can declare its messages.");
        }
        if (module != "" && (!safePath(module) || !~/\.(mjs|js)$/.match(module))) {
            throw new Exception("The frontend module must reference a JavaScript file in public/.");
        }
        if (stylesheet != ""
            && (!safePath(stylesheet) || !StringTools.endsWith(stylesheet, ".css"))) {
            throw new Exception("The stylesheet must reference a CSS file in public/.");
        }
        if ((module != "" || stylesheet != "") && !hooks.contains("site.assets")) {
            hooks.push("site.assets");
        }
        var serverJar = text(input.server, "jar", 240);
        var serverCppia = text(input.server, "cppia", 240);
        var serverPhp = text(input.server, "php", 240);
        var entrypoint = text(input.server, "entrypoint", 180);
        if (serverJar != "" || serverCppia != "" || serverPhp != "" || entrypoint != "") {
            var validJar = serverJar == ""
                || (safePath(serverJar) && StringTools.endsWith(serverJar, ".jar"));
            var validCppia = serverCppia == ""
                || (safePath(serverCppia) && StringTools.endsWith(serverCppia, ".cppia"));
            var validPhp = serverPhp == ""
                || (safePath(serverPhp) && StringTools.endsWith(serverPhp, ".json"));
            if (!validJar
                || !validCppia
                || !validPhp
                || (serverJar == "" && serverCppia == "" && serverPhp == "")
                || !~/^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)+$/.match(entrypoint)) {
                throw new Exception("Declare valid server modules and a fully qualified entrypoint class.");
            }
        }
        if (kind == "plugin"
            && module == ""
            && stylesheet == ""
            && serverJar == ""
            && serverCppia == ""
            && serverPhp == "") {
            throw new Exception("A plugin requires a server module or frontend assets.");
        }
        var frontendOnly = kind == "plugin"
            && serverJar == ""
            && serverCppia == ""
            && serverPhp == "";
        if (uploaded && frontendOnly) {
            var serverHooks = hooks.filter(event -> !hostEvents.contains(event));
            if (serverHooks.length > 0 || locks.length > 0) {
                throw new Exception("A plugin without a server module can only use the site.assets and i18n.catalogues hooks and holds no host locks.");
            }
        }
        var layout = text(input, "layout", 30);
        var designFile = text(input.design, "file", 240);
        var mediaFile = text(input.design, "media", 240);
        var mediaPrefix = text(input.design, "mediaPrefix", 500);
        if (designFile != ""
            && (kind != "theme"
                || layout != "builder"
                || !safePath(designFile)
                || !StringTools.endsWith(designFile, ".json"))) {
            throw new Exception("A visual theme design must reference a JSON file in its package.");
        }
        if (mediaFile != "" && (!safePath(mediaFile) || !StringTools.endsWith(mediaFile,
            ".json"))) {
            throw new Exception("A visual theme media list must reference a JSON file in its package.");
        }
        var translations = translationFiles(input.translations);
        if (Lambda.count(translations) > 0 && !hooks.contains("i18n.catalogues")) {
            hooks.push("i18n.catalogues");
        }
        if (kind == "theme") {
            if (!Slug.valid(layout)) {
                throw new Exception("A theme requires a valid layout name.");
            }
            if (stylesheet == "" && layout != "simple" && layout != "builder") {
                throw new Exception("A custom theme layout requires a stylesheet.");
            }
        }
        var manifest:ManifestData = {
            apiVersion: input.apiVersion,
            cmsVersion: text(input, "cmsVersion", 40),
            kind: kind,
            pluginId: identity == "" ? null : identity,
            slug: slug,
            name: text(input, "name", 100, true),
            version: version,
            description: text(input, "description", 500),
            author: text(input, "author", 100),
            hooks: hooks,
            fields: fields(input.fields),
            module: module,
            legacyRenderer: legacyRenderer,
            messages: messages,
            views: views,
            locks: locks,
            stylesheet: stylesheet,
            serverJar: serverJar,
            serverCppia: serverCppia,
            serverPhp: serverPhp,
            entrypoint: entrypoint,
            layout: layout,
            designFile: designFile,
            mediaFile: mediaFile,
            mediaPrefix: mediaPrefix,
            translations: translations,
            templates: templateDefinitions(input.templates),
            navigation: navigationDefinitions(input.navigation)
        };
        return manifest;
    }

    /** The catalogue keys a frontend module declares in `assets.messages`. **/
    static function messageKeys(input:Dynamic):Array<String> {
        if (input == null) {
            return [];
        }
        if (!Std.isOfType(input, Array)) {
            throw new Exception("Declare the frontend module's messages as a list of catalogue keys.");
        }
        var requested:Array<Dynamic> = input;
        if (requested.length > 200) {
            throw new Exception("A frontend module can declare at most 200 messages.");
        }
        var keys:Array<String> = [];
        for (key in requested) {
            if (!Std.isOfType(key, String) || key == "" || (key : String).length > 500) {
                throw new Exception("The frontend module's messages must be catalogue keys.");
            }
            if (!keys.contains(key)) {
                keys.push(key);
            }
        }
        return keys;
    }

    static function lockList(input:Dynamic):Array<String> {
        if (input == null) {
            return [];
        }
        if (!Std.isOfType(input, Array)) {
            throw new Exception("Package locks must be a list.");
        }
        var requested:Array<Dynamic> = input;
        for (name in requested) {
            if (!Std.isOfType(name, String) || !lockNames.contains(name)) {
                throw new Exception("The package requests an unsupported host lock.");
            }
        }
        return lockNames.filter(name -> requested.contains(name));
    }

    static function templateDefinitions(input:Dynamic):Array<{name:String, label:String, scope:String}> {
        if (input == null) {
            return [];
        }
        if (!(input is Array)) {
            throw new Exception("Declare public templates as a list.");
        }
        var source:Array<Dynamic> = input;
        if (source.length > 32) {
            throw new Exception("A theme can declare at most 32 public templates.");
        }
        var result:Array<{name:String, label:String, scope:String}> = [];
        var seen:Map<String, Bool> = [];
        for (entry in source) {
            var name = text(entry, "name", 80, true);
            var label = text(entry, "label", 100, true);
            var scope = text(entry, "scope", 20, true);
            if (!~/^[A-Za-z][A-Za-z0-9_-]{0,79}$/.match(name) || seen.exists(name)
                || !["detail", "archive", "home"].contains(scope)) {
                throw new Exception("Public templates require unique names and a detail, archive or home scope.");
            }
            seen.set(name, true);
            result.push({name: name, label: label, scope: scope});
        }
        return result;
    }

    static function navigationDefinitions(input:Dynamic):Array<{key:String, name:String, maxLinks:Int}> {
        if (input == null) {
            return [];
        }
        if (!(input is Array)) {
            throw new Exception("Declare theme navigation regions as a list.");
        }
        var source:Array<Dynamic> = input;
        if (source.length > 12) {
            throw new Exception("A theme can request at most 12 navigation regions.");
        }
        var result:Array<{key:String, name:String, maxLinks:Int}> = [];
        var seen:Map<String, Bool> = [];
        for (entry in source) {
            var key = text(entry, "key", 40, true);
            var name = text(entry, "name", 100, true);
            var maximum:Dynamic = entry.maxLinks ?? 12;
            if (!~/^[a-z][a-z0-9_-]{0,39}(?![\s\S])/.match(key)
                || seen.exists(key)
                || !Std.isOfType(maximum, Int)
                || maximum < 1
                || maximum > 50) {
                throw new Exception("Navigation regions require unique keys and link limits from 1 to 50.");
            }
            seen.set(key, true);
            result.push({key: key, name: name, maxLinks: maximum});
        }
        return result;
    }

    static function translationFiles(input:Dynamic):Map<String, String> {
        var files:Map<String, String> = [];
        if (input == null) {
            return files;
        }
        if (!Reflect.isObject(input) || Std.isOfType(input, String) || Std.isOfType(input, Array)) {
            throw new Exception("Declare translation files as a locale-to-path object.");
        }
        var locales = Reflect.fields(input);
        if (locales.length > 10) {
            throw new Exception("A package can declare at most 10 translation catalogues.");
        }
        for (locale in locales) {
            var path = text(input, locale, 240, true);
            if (!~/^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$/.match(locale) || !safePath(path)
                || !StringTools.endsWith(path, ".json")) {
                throw new Exception("Translation files require valid locale codes and safe JSON paths.");
            }
            files.set(locale, path);
        }
        return files;
    }

    public static function serverTarget():String {
        #if jvm
        return "jvm";
        #elseif (cpp && !cppia)
        return "cpp";
        #elseif php
        return "php";
        #else
        return "unsupported";
        #end
    }

    public static function serverArtifact(manifest:ManifestData):String {
        requireCompatible(manifest);
        var artifact = switch (serverTarget()) {
            case "jvm": manifest.serverJar;
            case "cpp": manifest.serverCppia;
            case "php": manifest.serverPhp;
            default: "";
        };
        if (artifact == "" && hasServer(manifest)) {
            throw new Exception('This package does not include a server module for the ${serverTarget()} target.');
        }
        return artifact;
    }

    /**
        An installed package's manifest, parsed once per text for the paths
        every request takes, such as the active theme and plugin hooks. The
        result is shared: callers must not change it.
    **/
    public static function stored(text:String):ManifestData {
        #if (target.threaded)
        storedLock.acquire();
        #end
        var found = storedManifests.get(text);
        #if (target.threaded)
        storedLock.release();
        #end
        if (found != null) {
            return found;
        }
        var parsed = parse(text);
        #if (target.threaded)
        storedLock.acquire();
        #end
        if (!storedManifests.exists(text)) {
            storedOrder.push(text);
            if (storedOrder.length > MAX_STORED) {
                storedManifests.remove(storedOrder.shift());
            }
        }
        storedManifests.set(text, parsed);
        #if (target.threaded)
        storedLock.release();
        #end
        return parsed;
    }

    public static function requireCompatible(manifest:ManifestData):Void {
        if (manifest.layout == "builder"
            && manifest.designFile != ""
            && (manifest.apiVersion != CmsVersion.pluginApiVersion
                || manifest.cmsVersion != CmsVersion.version)) {
            throw new Exception("Export this visual theme for this exact CMS release.");
        }
        if (manifest.legacyRenderer) {
            throw new Exception(RENDERER_UNSUPPORTED);
        }
        var serverModule = hasServer(manifest);
        if (manifest.kind != "plugin" && !serverModule) {
            return;
        }
        if (manifest.apiVersion != CmsVersion.pluginApiVersion) {
            throw new Exception('This plugin requires CMS plugin API ${CmsVersion.pluginApiVersion}. Rebuild it for this CMS release.');
        }
        if (manifest.cmsVersion != CmsVersion.version) {
            var target = manifest.cmsVersion == "" ? "an unspecified version" : manifest.cmsVersion;
            var message = 'This plugin targets CMS ${target}; this server runs CMS ${CmsVersion.version}.';
            throw new Exception('${message} An exact version match is required.');
        }
        // A plugin made only of frontend assets and translations runs no server code.
        if (serverModule && (manifest.serverJar == "" || manifest.serverCppia == "")) {
            throw new Exception("Every plugin ZIP must contain both a JAR and a CPPIA server module.");
        }
    }

    public static function hasServer(manifest:ManifestData):Bool {
        return manifest.serverJar != "" || manifest.serverCppia != "" || manifest.serverPhp != "";
    }

    static function fields(input:Dynamic):Array<PackageField> {
        if (input == null) {
            return [];
        }
        if (!Std.isOfType(input, Array)) {
            throw new Exception("Package settings must be a list.");
        }
        var values:Array<Dynamic> = input;
        if (values.length > 32) {
            throw new Exception("A package can define at most 32 settings.");
        }
        var result:Array<PackageField> = [];
        var keys:Array<String> = [];
        for (field in values) {
            var key = text(field, "key", 64, true);
            var kind = text(field, "kind", 20, true);
            if (!~/^[a-z][a-z0-9_]*(?![\s\S])/.match(key)
                || keys.contains(key)
                || !["text", "textarea", "boolean", "number", "color", "select", "secret"].contains(kind)) {
                throw new Exception("The package contains an invalid or duplicate setting.");
            }
            keys.push(key);
            var options:Array<SettingOption> = [];
            if (kind == "select") {
                if (!Std.isOfType(field.options, Array)) {
                    throw new Exception("Select settings require options.");
                }
                var choices:Array<Dynamic> = field.options;
                if (choices.length < 1 || choices.length > 20) {
                    throw new Exception("Select settings require between 1 and 20 options.");
                }
                for (choice in choices) {
                    options.push({
                        value: text(choice, "value", 80, true),
                        label: text(choice, "label", 100, true)
                    });
                }
            }
            var defaultValue = field.defaultValue == null ? "" : text(field, "defaultValue", 2000);
            if (kind == "secret" && defaultValue != "") {
                throw new Exception("Secret settings cannot include a default credential.");
            }
            var minimum = field.minimum == null ? -1000000000.0 : Std.parseFloat(Std.string(field.minimum));
            var maximum = field.maximum == null ? 1000000000.0 : Std.parseFloat(Std.string(field.maximum));
            if (!Math.isFinite(minimum) || !Math.isFinite(maximum) || minimum > maximum) {
                throw new Exception("The package contains an invalid number range.");
            }
            result.push({
                key: key,
                label: text(field, "label", 100, true),
                kind: kind,
                help: text(field, "help", 300),
                defaultValue: defaultValue,
                required: field.required == true,
                minimum: minimum,
                maximum: maximum,
                options: options
            });
        }
        return result;
    }
}
