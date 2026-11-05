package hx.press.middleware;

import hx.well.inertia.InertiaMiddleware;
import hx.press.install.InstallationState;
import hx.well.http.Request;
import hx.press.SiteSettingsStore;
import hx.press.i18n.I18n;
import hx.well.type.AttributeType;
import hx.well.route.RouteElement;
import hx.press.CategoryData;
import hx.well.facades.Environment;
import hx.press.plugins.PluginRuntime;
import hx.press.packages.ThemeData;
import hx.press.NavigationData;
import hx.press.content.ContentTypes;
import hx.press.themes.ThemeFeedData;
import hx.well.facades.Inertia;
import hx.press.media.MediaReferences;

class HandleInertiaRequests extends InertiaMiddleware {
    public override function share(request:Request):Dynamic {
        if (InstallationState.pending) {
            return {
                site: {site_name: "HaxePress"},
                theme: null,
                auth: null,
                csrfToken: null,
                errors: {}
            };
        }
        var path = request.path;
        var route:RouteElement = request.getAttribute(AttributeType.RouteElement);
        if (route != null && route.getAttribute("inertia.share", true) == false) {
            return {};
        }
        if (StringTools.startsWith(path, "/build/")
            || StringTools.startsWith(path, "/fonts/")
            || StringTools.startsWith(path, "/images/")
            || StringTools.startsWith(path, "/media/")
            || StringTools.startsWith(path, "/extension-assets/")
            || StringTools.startsWith(path, "/admin/extension-assets/")
            || StringTools.startsWith(path, "/packages/")
            || StringTools.startsWith(path, "/themes/")
            || path == "/favicon.svg"
            || path == "/categories/options"
            || path == "/admin/media/upload"
            || path == "/admin/plugins/upload"
            || path == "/admin/themes/upload"
            || path == "/admin/tags/options")
            return {};
        var settings = SiteSettingsStore.settings();
        var primaryType = ContentTypes.find(settings.get("home_type") ?? "entry");
        var archive = primaryType != null && primaryType.publicVisible
            && primaryType.hasArchive ? primaryType.publicBase : "/";
        var publicPage = path != "/admin" && !StringTools.startsWith(path, "/admin/");
        var theme = publicPage ? ThemeData.active() : null;
        var pluginAssets = publicPage ? PluginRuntime.assets() : [];
        var pluginBlocks = publicPage ? PluginRuntime.blocks("site.shared", {path: path}) : [];
        return {
            site: settings,
            i18n: I18n.props(),
            categories: [],
            primaryArchive: archive,
            auth: null,
            csrfToken: null,
            errors: {},
            theme: theme,
            mediaRules: MediaReferences.rules(),
            themeFeeds: () -> {
                var activeTheme:Dynamic = Inertia.getShared("theme");
                var selected:String = activeTheme != null
                    && activeTheme.studioScope != null ? activeTheme.studioScope : request.getAttribute("hx.press.theme.template",
                        "Home");
                return ThemeFeedData.resolve(activeTheme, selected,
                    request.getAttribute("hx.press.theme.fallback", "Home"));
            },
            navigation: publicPage ? NavigationData.forRegions(theme.navigation) : null,
            pluginNavigation: {
                header: publicPage ? PluginRuntime.navigation("header", []) : [],
                footer: publicPage ? PluginRuntime.navigation("footer", []) : [],
                admin: []
            },
            extensions: {
                assets: pluginAssets,
                blocks: pluginBlocks
            },
            siteUrl: Environment.env("APP_URL", "http://127.0.0.1:3000")
        };
    }
}
