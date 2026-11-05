package hx.press.packages;

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
import hx.press.NavigationData;
import hx.press.plugins.PluginRuntime;
import haxe.Exception;
import hx.well.facades.Config;
import hx.well.facades.Inertia;
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
        var designedThemes = kind == "theme" ? ThemeDesignData.identifiers(page.items.map(item ->
            item.id)) : [];
        var packages = page.items.map(item -> {
            var props:Dynamic = Reflect.copy(item);
            props.built_in = BuiltInTheme.isBuiltIn(item.id);
            props.designed = designedThemes.contains(item.id);
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
        var props:Map<String, Dynamic> = [
            "kind" => kind,
            "i18n" => Inertia.always(I18n.includePackages(I18n.props(),
                page.items.map(item -> item.id))),
            "packages" => packages,
            "themePreviewRevision" => themePreviewRevision,
            "query" => query,
            "total" => count,
            "pagination" => links,
            "notice" => notice,
            "uploadLimit" => uploadLimit
        ];
        if (error != "") {
            props.set("errors", ["package" => error]);
        }
        return Inertia.render("Admin/Extensions", props).status(status);
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
        try {
            var key = AdminController.input(request, "key", 64);
            if (!~/^[A-Za-z0-9_-]{32}$/.match(key)) {
                throw new Exception("Inspect a package ZIP before installing it.");
            }
            PackageManager.install(key, kind, admin.id, admin.name,
                request.input("replace", "0") == "1");
            return ResponseBuilder.asRedirect(base(kind) + "?notice=installed", 303);
        } catch (error:Dynamic) {
            return index(request, kind, Std.string(error), 422);
        }
    }

    public static function discard(request:Request, kind:String):AbstractResponse {
        if (!CmsAccess.can("extensions")) {
            return CmsController.forbidden(request);
        }
        var admin = CmsAccess.current();
        PackageManager.discard(AdminController.input(request, "key", 64), admin.id);
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
            return ResponseBuilder.asRedirect(base(kind) + "?notice=" + notice, 303);
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
        var url = base(kind) + "/" + id + "/settings";
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
        var props:Map<String, Dynamic> = [
            "kind" => kind,
            "i18n" => Inertia.always(I18n.props(PackageData.one(id))),
            "packageInfo" => {
                id: item.id,
                name: item.name,
                version: item.version
            },
            "fields" => manifest.fields,
            "values" => configured,
            "secrets" => secrets,
            "notice" => request.query("notice",
                "") == "saved" ? "Package settings have been saved." : ""
        ];
        if (error != "") {
            props.set("errors", ["package" => error]);
        }
        return Inertia.render("Admin/ExtensionSettings", props).status(status);
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
        var previewBase = "/admin/themes/" + theme.id + "/preview/frame";
        var previewUrl = previewBase + "?lang=" + StringTools.urlEncode(I18n.locale());
        var manifest = PackageManifest.parse(theme.manifest);
        var fields = manifest.fields.filter(field -> field.kind != "secret");
        var customization:Dynamic = null;
        if (fields.length > 0) {
            var session = SecureToken.generate(32);
            var values = PackageSettings.values(manifest, theme.settings, false);
            customization = {fields: fields, values: values, session: session};
            previewUrl += "&customizeSession=" + session;
        }
        var redirect = AdminController.validationRedirect(request, "package", error,
            "/admin/themes/" + theme.id + "/preview");
        if (redirect != null) {
            return redirect;
        }
        var props:Map<String, Dynamic> = [
            "preview" => {
                id: theme.id,
                name: theme.name,
                url: previewUrl,
                customization: customization
            },
            "i18n" => I18n.props(theme),
            "notice" => request.query("notice",
                "") == "saved" ? "Theme changes have been saved." : ""
        ];
        if (error != "") {
            props.set("errors", ["package" => error]);
        }
        return Inertia.render("Admin/ThemePreview", props).status(status);
    }

    public static function previewContent(request:Request, path:String = "/"):AbstractResponse {
        if (!CmsAccess.can("extensions")) {
            return CmsController.forbidden(request);
        }
        var theme = PackageData.one(request.route("id"));
        if (theme == null || theme.kind != "theme") {
            return SiteController.notFound(request);
        }
        var previewBase = "/admin/themes/" + theme.id + "/preview/frame";
        request.setAttribute("hx.press.preview.base", previewBase);
        var themeInfo = ThemeData.info(theme, true);
        themeInfo.preview = false;
        themeInfo.previewBase = previewBase;
        var session = request.query("customizeSession", "");
        if (~/^[A-Za-z0-9_-]{32}$/.match(session)) {
            themeInfo.customizeSession = session;
        }
        Inertia.share("theme", themeInfo);
        Inertia.share("i18n", I18n.props(theme));
        Inertia.share("categories", CategoryData.names());
        Inertia.share("navigation", NavigationData.forRegions(themeInfo.navigation));
        Inertia.share("extensions", {
            assets: PluginRuntime.assets(),
            blocks: PluginRuntime.blocks("site.shared", {path: path})
        });
        Inertia.share("pluginNavigation", {
            header: PluginRuntime.navigation("header", []),
            footer: PluginRuntime.navigation("footer", []),
            admin: []
        });
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
