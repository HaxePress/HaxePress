package hx.press.view;

import hx.press.CmsAccess;
import hx.press.NavigationData;
import hx.press.SiteSettingsStore;
import hx.press.AdminNavigation;
import hx.press.access.Roles;
import hx.press.content.ContentTypes;
import hx.press.i18n.I18n;
import hx.press.media.MediaReferences;
import hx.press.packages.ThemeData;
import hx.press.plugins.PluginHealth;
import hx.press.plugins.PluginRuntime;
import hx.press.themes.ThemeFeedData;
import hx.well.facades.Environment;
import hx.well.http.Request;

/**
    Computes the implicit roots of HaxePress templates on first read. A
    template that never reads `adminNavigation` never builds it. Values
    shared with `View.share` for one request take precedence.
**/
class ViewRoots {
    public static final names = [
        "site",
        "i18n",
        "auth",
        "request",
        "theme",
        "navigation",
        "pluginNavigation",
        "extensions",
        "adminNavigation",
        "errors",
        "primaryArchive",
        "siteUrl",
        "csrfToken",
        "pluginRestartRequired",
        "adminSidebar",
        "adminLocation",
        "translations"
    ];

    public static function resolve(name:String, host:ViewHost):Dynamic {
        var request = host.request;
        var shared = View.shared(request);
        if (shared != null && shared.exists(name)) {
            return shared.get(name);
        }
        return switch name {
            case "site":
                SiteSettingsStore.settings();
            case "i18n":
                i18n();
            case "auth":
                auth();
            case "request":
                requestView(request);
            case "theme":
                isAdmin(request) ? null : ThemeData.active();
            case "navigation":
                var theme:Dynamic = host.root("theme");
                theme == null ? new Map<String,
                    Dynamic>() : NavigationData.forRegions(theme.navigation);
            case "pluginNavigation":
                pluginNavigation(host);
            case "extensions":
                extensions(host);
            case "adminNavigation":
                adminNavigation(request);
            case "errors":
                View.errors(request, host.props);
            case "primaryArchive":
                primaryArchive();
            case "siteUrl":
                Environment.env("APP_URL", "http://127.0.0.1:3000");
            case "csrfToken":
                host.csrfToken();
            case "pluginRestartRequired":
                PluginHealth.restartRequired;
            case "themeFeeds":
                var theme:Dynamic = host.root("theme");
                var selected:String = theme != null
                    && theme.studioScope != null ? theme.studioScope : request == null ? "Home" : request.getAttribute("hx.press.theme.template",
                        "Home");
                ThemeFeedData.resolve(theme, selected,
                    request == null ? "Home" : request.getAttribute("hx.press.theme.fallback",
                        "Home"));
            case "adminSidebar":
                AdminChrome.sidebar(host.root("adminNavigation"), request);
            case "adminLocation":
                AdminChrome.location(host.root("adminNavigation"), request, host);
            case "translations":
                Translations.url();
            default:
                null;
        }
    }

    public static function isAdmin(request:Null<Request>):Bool {
        if (request == null) {
            return false;
        }
        var path = request.path;
        return path == "/admin" || StringTools.startsWith(path, "/admin/");
    }

    /** Templates read the locale and its direction; the catalogues stay out of page rendering. **/
    static function i18n():Dynamic {
        var selected = I18n.locale();
        return {
            locale: selected,
            direction: I18n.direction(selected),
            locales: I18n.locales
        };
    }

    public static function auth():Dynamic {
        var admin = CmsAccess.current();
        if (admin == null) {
            return null;
        }
        return {
            admin: {
                id: admin.id,
                name: admin.name,
                email: admin.email,
                role: admin.role,
                roleLabel: Roles.label(admin.role),
                capabilities: Roles.grants(admin.role)
            }
        };
    }

    static function requestView(request:Null<Request>):Dynamic {
        if (request == null) {
            return {
                path: "/",
                url: "/",
                method: "GET",
                query: new Map<String, String>()
            };
        }
        var query:Map<String, String> = [];
        var pairs:Array<String> = [];
        for (key => value in request.queries) {
            query.set(key, value);
            pairs.push('${StringTools.urlEncode(key)}=${StringTools.urlEncode(value)}');
        }
        var search = pairs.length == 0 ? "" : '?${pairs.join("&")}';
        return {
            path: request.path,
            url: '${request.path}${search}',
            method: request.method,
            query: query
        };
    }

    static function pluginNavigation(host:ViewHost):Dynamic {
        var request = host.request;
        if (isAdmin(request)) {
            var admin = CmsAccess.current();
            var grants = admin == null ? [] : Roles.grants(admin.role);
            return {
                header: [],
                footer: [],
                admin: admin == null ? [] : PluginRuntime.navigation("admin", grants.copy())
            };
        }
        var theme:Dynamic = host.root("theme");
        return {
            header: theme == null ? [] : PluginRuntime.navigation("header", []),
            footer: theme == null ? [] : PluginRuntime.navigation("footer", []),
            admin: []
        };
    }

    static function extensions(host:ViewHost):Dynamic {
        var theme:Dynamic = host.root("theme");
        var request = host.request;
        return {
            assets: theme == null ? [] : PluginRuntime.assets(),
            blocks: theme == null ? [] : PluginRuntime.blocks("site.shared", {
                path: request == null ? "/" : request.path
            })
        };
    }

    /** The administration menu groups the signed-in member may open, with plugin links. **/
    public static function adminNavigation(request:Null<Request>):Dynamic {
        var admin = CmsAccess.current();
        if (admin == null || request == null) {
            return [];
        }
        var grants = Roles.grants(admin.role);
        var pluginLinks = PluginRuntime.navigation("admin", grants.copy());
        return AdminNavigation.groups(request, pluginLinks, grants);
    }

    public static function primaryArchive():String {
        var settings = SiteSettingsStore.settings();
        var primaryType = ContentTypes.find(settings.get("home_type") ?? "entry");
        return primaryType != null && primaryType.publicVisible
            && primaryType.hasArchive ? primaryType.publicBase : "/";
    }

    public static function mediaRules():Dynamic {
        return MediaReferences.rules();
    }
}
