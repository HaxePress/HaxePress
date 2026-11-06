package hx.press.themes;

import haxe.Json;
import hx.press.CmsAccess;
import hx.press.CmsController;
import hx.press.ContentItemData;
import hx.press.ContentQueries;
import hx.press.NavigationData;
import hx.press.SiteController;
import hx.press.SiteSettingsStore;
import hx.press.content.ContentTypes;
import hx.press.i18n.I18n;
import hx.press.packages.PackageData;
import hx.press.packages.ThemeData;
import hx.press.plugins.PluginRuntime;
import hx.well.facades.Inertia;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.internal.SecureToken;
import hx.press.model.ContentType;

class ThemeStudioController {
    public static function create(request:Request):AbstractResponse {
        if (!CmsAccess.can("extensions")) {
            return CmsController.forbidden(request);
        }
        var props = {baseDocument: ThemeDesignSchema.starter(true)};
        return Inertia.render("Admin/ThemeCreate", props);
    }

    public static function editor(request:Request):AbstractResponse {
        if (!CmsAccess.can("extensions")) {
            return CmsController.forbidden(request);
        }
        var id = request.route("id");
        var theme = PackageData.one(id);
        var design = ThemeDesignData.editor(id);
        if (theme == null || theme.kind != "theme" || design == null) {
            return SiteController.notFound(request);
        }
        var session = SecureToken.generate(32);
        var document:Dynamic = ThemeDesignSchema.parse(design.draft);
        var collections = ContentTypes.available(ContentType.query.select(["key", "name"]))
            .where("public_visible", 1)
            .orderBy("position")
            .orderBy("key")
            .limit(64)
            .get()
            .map(model -> model.toObject());
        var props = {
            studio: {
                id: id,
                name: theme.name,
                enabled: theme.enabled == 1,
                document: document,
                imageRules: ThemeAssets.rules(id),
                collections: collections,
                version: design.version,
                publishedVersion: design.published_version,
                session: session,
                frameUrl: '/admin/themes/${id}/design/frame?studioSession=${session}'
            }
        };
        return Inertia.render("Admin/ThemeBuilder", props);
    }

    public static function frame(request:Request):AbstractResponse {
        if (!CmsAccess.can("extensions")) {
            return CmsController.forbidden(request);
        }
        var id = request.route("id");
        var theme = PackageData.one(id);
        var design = ThemeDesignData.editor(id);
        if (theme == null || theme.kind != "theme" || design == null) {
            return SiteController.notFound(request);
        }
        var document:Dynamic = ThemeDesignSchema.parse(design.draft);
        var template = request.query("template", "Home").substr(0, 81);
        var component = StringTools.startsWith(template, "@");
        var exists = component ? Reflect.hasField(document.components,
            template.substr(1)) : Reflect.hasField(document.templates, template);
        var validName = component ? ~/^@[A-Za-z0-9_-]{1,40}$/.match(template) : ~/^[A-Za-z][A-Za-z0-9_-]{0,79}$/.match(template)
            && !StringTools.startsWith(template, "Admin");
        if (!exists && !validName) {
            template = "Home";
        }
        var metadata = Reflect.field(document.templateMeta, template);
        var fallback:String = metadata == null ? request.query("fallback",
            ThemeDesignSchema.templates.contains(template) ? template : "Home") : metadata.fallback;
        if (!ThemeDesignSchema.templates.contains(fallback) || component) {
            fallback = "Home";
        }
        request.setAttribute("hx.press.theme.template", template);
        var info = ThemeData.info(theme, true);
        info.design = document;
        info.studioScope = template;
        var session = request.query("studioSession", "");
        if (~/^[A-Za-z0-9_-]{32}$/.match(session)) {
            info.studioSession = session;
        }
        Inertia.share("theme", info);
        Inertia.share("i18n", I18n.props(theme));
        Inertia.share("navigation", NavigationData.forRegions(["header", "footer"]));
        var homeType = SiteSettingsStore.settings().get("home_type") ?? "entry";
        var kind = request.query("collection", fallback == "Page" ? "page" : homeType)
            .substr(0, 32);
        var type = ContentTypes.find(kind);
        if (type == null || !type.publicVisible) {
            type = ContentTypes.find(homeType);
        }
        var path = switch (fallback) {
            case "Home": "/";
            case "About": "/about";
            default: type == null ? "/" : type.publicBase;
        };
        Inertia.share("extensions", {
            assets: PluginRuntime.assets(),
            blocks: PluginRuntime.blocks("site.shared", {path: path})
        });
        Inertia.share("pluginNavigation", {
            header: PluginRuntime.navigation("header", []),
            footer: PluginRuntime.navigation("footer", []),
            admin: []
        });
        if (fallback == "Home") {
            return SiteController.home(request);
        }
        if (fallback == "ContentIndex" && type != null) {
            return SiteController.index(request, type.key);
        }
        if ((fallback == "ContentDetail" || fallback == "Page") && type != null) {
            var selectedId = Std.parseInt(request.query("sample", "0")) ?? 0;
            var record = selectedId > 0 ? ContentQueries.publishedById(selectedId) : null;
            if (record == null || record.content_type != type.key) {
                var latest = ContentQueries.latest(0, type.key, 1);
                record = latest.length == 0 ? null : ContentQueries.publishedById(latest[0].id);
            }
            if (record != null) {
                return SiteController.renderDocument(request, record, type);
            }
        }
        var props = {
            items: [],
            featured: null,
            item: null,
            collection: type == null ? null : ContentTypes.publicInfo(type),
            templateFallback: fallback
        };
        return Inertia.render(component ? "Home" : template, props);
    }
}
