package hx.press.packages;

import haxe.Json;
import hx.press.view.PackageFieldViews;
import hx.press.view.PackageFieldViews;
import hx.press.view.View;
import hx.press.view.types.AdminViews.ThemePreviewView;
import hx.press.AdminController;
import hx.press.SiteController;
import hx.press.Pagination;
import hx.press.CategoryData;
import hx.press.i18n.I18n;
import hx.press.CmsAccess;
import hx.press.CmsController;
import hx.press.handler.SitePublicHandler;
import hx.press.TagData;
import hx.press.SiteSettingsStore;
import haxe.Exception;
import haxe.ds.StringMap;
import hx.press.packages.PackageManifest.PackageField;
import hx.well.facades.Config;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.ResponseBuilder;
import hx.press.model.InstalledPackage;
import hx.press.ContentCache;
import haxe.crypto.Md5;
import hx.well.internal.SecureToken;
import hx.press.themes.ThemeDesignData;

class PackageController {
    public static function base(kind:String):String {
        return kind == "theme" ? "/admin/themes" : "/admin/plugins";
    }

    public static function index(request:Request, kind:String, error:String = "",
            status:Int = 200):AbstractResponse {
        if (!CmsAccess.can("extensions")) {
            return CmsController.forbidden(request);
        }
        var url = base(kind);
        var redirect = AdminController.validationRedirect(request, "package", error, url);
        if (redirect != null) {
            return redirect;
        }
        var query = StringTools.trim(request.query("q", "")).substr(0, 80);
        var cursor = Pagination.cursor(request, true);
        var page = PackageData.page(kind, query, cursor);
        var count = PackageData.count(kind, query);
        var links = Pagination.links(url, ["q" => query], page, cursor, count, item -> item.id,
            item -> null);
        var notice = switch (request.query("notice", "")) {
            case "installed": "The package has been installed. Configure it and activate it when ready.";
            case "enabled": kind == "theme" ? "Your website now uses this theme." : "The plugin is active.";
            case "disabled": "The plugin has been deactivated.";
            case "removed": "The package has been removed.";
            default: "";
        };
        var serverLimit:Int = Config.get("http.max_content_length");
        var uploadLimit = serverLimit > 0 ? Std.int(Math.min(serverLimit,
            SafePackageArchive.MAX_BYTES)) : SafePackageArchive.MAX_BYTES;
        var publishStates:Map<String,
            Bool> = kind == "theme" ? ThemeDesignData.publishStates(page.items.map(item ->
                item.id)) : [];
        var packages = page.items.map(item -> {
            var props:Dynamic = Reflect.copy(item);
            props.built_in = BuiltInTheme.isBuiltIn(item.id)
                || BuiltInPlugins.isBuiltIn(item.id, item.plugin_id);
            props.designed = publishStates.exists(item.id);
            props.unpublished = publishStates.get(item.id) == true;
            return props;
        });
        var themePreviewRevision = "";
        if (kind == "theme") {
            var domains = [
                "items",
                "categories",
                "tags",
                "settings",
                "navigation",
                "structure",
                "extensions",
                "media"
            ];
            var revisions = domains.map(domain -> ContentCache.revision(domain));
            themePreviewRevision = Md5.encode(revisions.join(":"));
        }
        var translations = I18n.includePackages(I18n.props(), page.items.map(item -> item.id));
        var listed = PackageViews.packages(packages, translations, kind, themePreviewRevision);
        var inspection = PackageViews.inspection(request, kind);
        var github = PackageViews.github(request, kind);
        var uploadMegabytes = Math.floor(uploadLimit / 1024 / 1024);
        var props:Map<String, Dynamic> = [
            "kind" => kind,
            "i18n" => translations,
            "packages" => listed,
            "themePreviewRevision" => themePreviewRevision,
            "query" => query,
            "total" => count,
            "pagination" => links,
            "notice" => notice,
            "uploadLimit" => uploadLimit,
            "githubAvailable" => #if jvm kind == "plugin" #else false #end,
            "base" => url,
            "inspection" => inspection,
            "github" => github,
            "uploadMegabytes" => uploadMegabytes,
            "uploadDisabled" => inspection != null || github != null,
            "kindLabel" => count == 1 ? kind : '${kind}s'
        ];
        if (error != "") {
            props.set("errors", ["package" => error]);
        }
        return View.render("Admin/Extensions", props).status(status);
    }

    public static function upload(request:Request, kind:String):AbstractResponse {
        if (!CmsAccess.can("extensions")) {
            return ResponseBuilder.asJson({error: "Only an owner can install packages."}, 403);
        }
        var admin = CmsAccess.current();
        var bytes = request.bodyBytes;
        if (bytes == null || bytes.length == 0 || bytes.length > SafePackageArchive.MAX_BYTES) {
            return ResponseBuilder.asJson({error: "Choose a ZIP package smaller than 64 MB."}, 422);
        }
        try {
            var inspection = PackageManager.stage(bytes, kind, admin.id);
            return ResponseBuilder.asJson(inspection, 201);
        } catch (error:Dynamic) {
            return ResponseBuilder.asJson({error: Std.string(error)}, 422);
        }
    }

    public static function install(request:Request, kind:String):AbstractResponse {
        if (!CmsAccess.can("extensions")) {
            return CmsController.forbidden(request);
        }
        var admin = CmsAccess.current();
        var key = AdminController.input(request, "key", 64);
        try {
            if (!~/^[A-Za-z0-9_-]{32}$/.match(key)) {
                throw new Exception("Inspect a package ZIP before installing it.");
            }
            PackageManager.install(key, kind, admin.id, admin.name,
                request.input("replace", "0") == "1");
            return ResponseBuilder.asRedirect('${base(kind)}?notice=installed', 303);
        } catch (error:Dynamic) {
            // A failed installation keeps its inspection open, as the page did before.
            var inspected = ~/^[A-Za-z0-9_-]{32}$/.match(key) ? '${base(kind)}?inspect=${key}' : base(kind);
            var redirect = AdminController.validationRedirect(request, "package",
                Std.string(error), inspected);
            if (redirect != null) {
                return redirect;
            }
            return index(request, kind, Std.string(error), 422);
        }
    }

    public static function discard(request:Request, kind:String):AbstractResponse {
        if (!CmsAccess.can("extensions")) {
            return CmsController.forbidden(request);
        }
        var admin = CmsAccess.current();
        PackageManager.discard(AdminController.input(request, "key", 64), admin.id);
        if (View.redirectsValidation(request)) {
            return ResponseBuilder.asRedirect(base(kind), 303);
        }
        return ResponseBuilder.asJson({discarded: true});
    }

    public static function action(request:Request, kind:String, action:String):AbstractResponse {
        if (!CmsAccess.can("extensions")) {
            return CmsController.forbidden(request);
        }
        var id = request.route("id");
        var packageData = PackageData.one(id);
        if (packageData == null || packageData.kind != kind) {
            return SiteController.notFound(request);
        }
        var admin = CmsAccess.current();
        try {
            switch (action) {
                case "enable":
                    PackageManager.enable(id, admin.id, admin.name);
                case "disable":
                    PackageManager.disable(id, admin.id, admin.name);
                case "uninstall":
                    PackageManager.uninstall(id, admin.id, admin.name);
                default:
                    throw new Exception("Unsupported package action.");
            }
            var notice = action == "enable" ? "enabled" : action == "disable" ? "disabled" : "removed";
            return ResponseBuilder.asRedirect('${base(kind)}?notice=${notice}', 303);
        } catch (error:Dynamic) {
            return index(request, kind, Std.string(error), 422);
        }
    }

    public static function settings(request:Request, kind:String, error:String = "",
            status:Int = 200):AbstractResponse {
        if (!CmsAccess.can("extensions")) {
            return CmsController.forbidden(request);
        }
        var id = request.route("id");
        var item = InstalledPackage.query.where("id", id).where("kind", kind).limit(1).first();
        if (item == null) {
            return SiteController.notFound(request);
        }
        var url = '${base(kind)}/${id}/settings';
        var redirect = AdminController.validationRedirect(request, "package", error, url);
        if (redirect != null) {
            return redirect;
        }
        var manifest = PackageManifest.parse(item.manifest);
        var configured = PackageSettings.values(manifest, item.settings, false);
        var stored = PackageSettings.stored(item.settings);
        var secrets:Map<String, Bool> = [];
        for (field in manifest.fields) {
            if (field.kind == "secret") {
                configured.set(field.key, "");
                secrets.set(field.key, stored.get(field.key) != null && stored.get(field.key) != "");
            }
        }
        var shown = submittedSettings(request, manifest.fields, configured, error);
        var settingFields = PackageFieldViews.prepare(item.id, manifest.fields, shown, secrets);
        var props:Map<String, Dynamic> = [
            "kind" => kind,
            "i18n" => I18n.props(PackageData.one(id)),
            "packageInfo" => {
                id: item.id,
                name: item.name,
                version: item.version
            },
            "fields" => manifest.fields,
            "values" => configured,
            "secrets" => secrets,
            "notice" => request.query("notice",
                "") == "saved" ? "Package settings have been saved." : "",
            "packageName" => I18n.t(item.name, null, item.id),
            "settingFields" => settingFields,
            "base" => base(kind)
        ];
        if (error != "") {
            props.set("errors", ["package" => error]);
        }
        return View.render("Admin/ExtensionSettings", props).status(status);
    }

    /**
        The values a failed save submitted, from the request when its
        response renders the form, or flashed by its redirect. Secrets are
        never shown again.
    **/
    static function submittedSettings(request:Request, fields:Array<PackageField>,
            configured:Map<String, String>, error:String):Map<String, String> {
        var flashed:Dynamic = View.flashed(request, "old");
        var source:Null<Map<String, Dynamic>> = error != "" ? request.all() : Std.isOfType(flashed,
            StringMap) ? cast flashed : null;
        if (source == null) {
            return configured;
        }
        var shown = configured.copy();
        for (field in fields) {
            var value:Dynamic = source.get(field.key);
            if (field.kind != "secret" && Std.isOfType(value, String)) {
                shown.set(field.key, value);
            }
        }
        return shown;
    }

    public static function preview(request:Request, error:String = "",
            status:Int = 200):AbstractResponse {
        if (!CmsAccess.can("extensions")) {
            return CmsController.forbidden(request);
        }
        var theme = PackageData.one(request.route("id"));
        if (theme == null || theme.kind != "theme") {
            return SiteController.notFound(request);
        }
        var redirect = AdminController.validationRedirect(request, "package", error,
            '/admin/themes/${theme.id}/preview');
        if (redirect != null) {
            return redirect;
        }
        var previewBase = '/admin/themes/${theme.id}/preview/frame';
        var previewUrl = '${previewBase}?lang=${StringTools.urlEncode(I18n.locale())}';
        var manifest = PackageManifest.parse(theme.manifest);
        var fields = manifest.fields.filter(field -> field.kind != "secret");
        var saved:Map<String, String> = [];
        var editing:Map<String, String> = [];
        var dirty = false;
        if (fields.length > 0) {
            var session = SecureToken.generate(32);
            previewUrl += '&customizeSession=${session}';
            var values = PackageSettings.values(manifest, theme.settings, false);
            for (field in fields) {
                var stored = values.get(field.key) ?? "";
                var submitted = View.old(request, field.key);
                saved.set(field.key, stored);
                editing.set(field.key, submitted ?? stored);
                dirty = dirty || (submitted != null && submitted != stored);
            }
        }
        var notice = request.query("notice", "") == "saved" ? "Theme changes have been saved." : "";
        var errorMessage = View.errorText(View.errors(request, null).get("package"));
        var preview:ThemePreviewView = {
            id: theme.id,
            name: I18n.installedT(theme.name, null, theme.id),
            url: previewUrl,
            customizable: fields.length > 0,
            dirty: dirty,
            fields: PackageFieldViews.prepare(theme.id, fields, editing),
            saved: saved
        };
        var props:Map<String, Dynamic> = [
            "preview" => preview,
            "customizerOpen" => preview.customizable && (notice != "" || errorMessage != ""),
            "notice" => notice,
            "error" => errorMessage
        ];
        return View.render("Admin/ThemePreview", props).status(status);
    }

    /**
        Unsaved customizer values for a preview frame, sent as JSON in the
        `preview_settings` query: only the theme's own setting keys, as text.
    **/
    static function draftSettings(request:Request, saved:Map<String, String>):Map<String, String> {
        var raw = request.query("preview_settings", "");
        if (raw == "" || raw.length > 20000) {
            return saved;
        }
        var settings = saved.copy();
        try {
            var values:Dynamic = Json.parse(raw);
            for (key in saved.keys()) {
                var value:Dynamic = Reflect.field(values, key);
                if (Std.isOfType(value, String) && (value : String).length <= 2000) {
                    settings.set(key, value);
                }
            }
        } catch (error:Dynamic) {
            return saved;
        }
        return settings;
    }

    public static function previewContent(request:Request, path:String = "/"):AbstractResponse {
        if (!CmsAccess.can("extensions")) {
            return CmsController.forbidden(request);
        }
        var theme = PackageData.one(request.route("id"));
        if (theme == null || theme.kind != "theme") {
            return SiteController.notFound(request);
        }
        var previewBase = '/admin/themes/${theme.id}/preview/frame';
        request.setAttribute("hx.press.preview.base", previewBase);
        // `design=draft` shows a builder theme's saved draft, as AI design checks need.
        var draftDesign = request.query("design", "") == "draft";
        var themeInfo = ThemeData.info(theme, true, draftDesign);
        themeInfo.preview = false;
        themeInfo.previewBase = previewBase;
        var session = request.query("customizeSession", "");
        if (~/^[A-Za-z0-9_-]{32}$/.match(session)) {
            themeInfo.customizeSession = session;
        }
        if (themeInfo.customizeSession != null) {
            themeInfo.settings = draftSettings(request, themeInfo.settings);
        }
        View.shareAll(SiteController.appearance(themeInfo, path));
        if (path == "/") {
            return SiteController.home(request);
        }
        if (path == "/about") {
            return SiteController.about(request);
        }
        var tagPath = ~/^\/tags\/([a-z0-9-]+)$/;
        if (tagPath.match(path)) {
            var tag = TagData.named(tagPath.matched(1));
            var kind = request.query("type",
                SiteSettingsStore.settings().get("home_type") ?? "entry");
            return tag == null ? SiteController.notFound(request) : SiteController.index(request,
                kind, tag);
        }
        var response = SitePublicHandler.collection(request, path);
        return response == null ? SiteController.notFound(request) : response;
    }
}
