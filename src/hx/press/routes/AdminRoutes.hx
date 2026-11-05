package hx.press.routes;

import hx.well.route.Route;
import hx.well.route.RouteGroup;
import hx.press.AdminController;
import hx.press.CmsController;
import hx.press.ContentWorkflow;
import hx.press.MediaController;
import hx.press.ManagementController;
import hx.press.content.ContentTypeController;
import hx.press.access.RoleController;
import hx.press.content.ContentOptions;
import hx.press.packages.PackageController;
import hx.press.themes.ThemeStudioController;
import hx.press.themes.ThemeAssetController;
import hx.press.handler.admin.packages.UploadThemeImageHandler;
import hx.press.handler.admin.packages.SaveThemeDesignHandler;
import hx.press.handler.admin.packages.PreviewThemeSourcesHandler;
import hx.press.handler.admin.packages.ExportThemeDesignHandler;
import hx.press.themes.ThemeAiController;
import hx.press.themes.ThemeMcpWebSocket;
import hx.press.middleware.ThemeBrowserMcpMiddleware;
import hx.press.handler.admin.packages.SaveThemeAiPermissionsHandler;
import hx.press.handler.ExtensionAssetHandler;
import hx.press.middleware.AdminMiddleware;
import hx.press.middleware.AdminSessionMiddleware;
import hx.press.middleware.AdminInertiaProps;
import hx.well.middleware.AbstractMiddleware;
import hx.well.middleware.SessionMiddleware;
import hx.well.middleware.CsrfMiddleware;
import hx.well.middleware.SessionAuthMiddleware;
import hx.press.handler.admin.auth.LoginHandler;
import hx.press.handler.admin.auth.LogoutHandler;
import hx.press.handler.admin.settings.SaveSettingsHandler;
import hx.press.handler.admin.settings.ChangePasswordHandler;
import hx.press.handler.admin.media.UploadImageHandler;
import hx.press.handler.admin.category.ListCategoriesHandler;
import hx.press.handler.admin.category.SaveCategoryHandler;
import hx.press.handler.admin.category.DeleteCategoryHandler;
import hx.press.handler.admin.account.SaveAccountHandler;
import hx.press.handler.admin.media.SaveMediaHandler;
import hx.press.handler.admin.navigation.SaveNavigationHandler;
import hx.press.handler.admin.packages.SavePackageSettingsHandler;
import hx.press.handler.admin.tag.SaveTagHandler;
import hx.press.handler.admin.team.SaveMemberHandler;
import hx.press.handler.admin.content.SaveContentTypeHandler;
import hx.press.handler.admin.role.SaveRoleHandler;
import hx.press.handler.admin.navigation.SaveNavigationRegionHandler;

using hx.well.tools.RouteElementTools;

class AdminRoutes extends RouteGroup {
    public static function extension(callback:Void->Void):Void {
        var middlewares:Array<Class<AbstractMiddleware>> = [
            SessionMiddleware,
            AdminSessionMiddleware,
            CsrfMiddleware,
            SessionAuthMiddleware,
            AdminInertiaProps,
            AdminMiddleware
        ];
        Route.path("/admin").middleware(middlewares).group(callback);
    }

    public function template():Void {
        var sessionMiddleware:Array<Class<AbstractMiddleware>> = [
            SessionMiddleware,
            AdminSessionMiddleware,
            CsrfMiddleware,
            SessionAuthMiddleware,
            AdminInertiaProps
        ];
        Route.middleware(sessionMiddleware).group(() -> {
            Route.get("/login", AdminController.loginPage);
            Route.post("/login", new LoginHandler());
        });

        var protectedMiddleware = sessionMiddleware.copy();
        protectedMiddleware.push(AdminMiddleware);
        Route.middleware(protectedMiddleware).group(() -> {
            LegacyContentRoutes.registerAdmin();
            Route.get("/", AdminController.dashboard).attribute("cms.navigation", {
                group: "Content",
                groupPosition: 0,
                label: "Overview",
                icon: "layout",
                capability: "content",
                position: 0,
                exact: true
            });
            Route.post("/logout", new LogoutHandler());
            CollectionRoutes.register("/content", request -> "entry");
            CollectionRoutes.register("/pages", request -> "page");
            CollectionRoutes.register("/collections/{kind}", request -> request.route("kind"));
            Route.get("/collections", ContentTypeController.index).attribute("cms.navigation", {
                group: "Content",
                groupPosition: 0,
                label: "All collections",
                activePaths: ["/admin/content-types"],
                anyCapabilities: ["settings"],
                icon: "layers",
                capability: "content",
                position: 30,
                exact: true
            });
            Route.get("/content-options", ContentOptions.published);
            Route.get("/content-types/new", request -> ContentTypeController.editor(request, true));
            Route.get("/content-types/options", ContentTypeController.options);
            Route.get("/content-types/{key}/edit",
                request -> ContentTypeController.editor(request));
            Route.post("/content-types/create", new SaveContentTypeHandler());
            Route.post("/content-types/{key}/save", new SaveContentTypeHandler());
            Route.post("/content-types/{key}/delete", ContentTypeController.remove);
            Route.post("/content/publish-due", ContentWorkflow.runDue);
            Route.post("/media/upload", new UploadImageHandler());
            Route.get("/media", request -> MediaController.index(request))
                .attribute("cms.navigation", {
                    group: "Content",
                    groupPosition: 0,
                    label: "Media library",
                    icon: "image",
                    capability: "media",
                    position: 40,
                    exact: false
                });
            Route.post("/media/{id}/save", new SaveMediaHandler()).whereNumber("id");
            Route.post("/media/{id}/delete", MediaController.delete).whereNumber("id");
            Route.get("/media/{id}/references", MediaController.references).whereNumber("id");
            Route.get("/categories", new ListCategoriesHandler()).attribute("cms.navigation", {
                group: "Organization",
                groupPosition: 10,
                label: "Categories",
                icon: "grid",
                capability: "taxonomy",
                position: 0,
                exact: false
            });
            Route.post("/categories/save", new SaveCategoryHandler());
            Route.post("/categories/{id}/delete", new DeleteCategoryHandler()).whereNumber("id");
            Route.get("/tags", request -> CmsController.tags(request)).attribute("cms.navigation", {
                group: "Organization",
                groupPosition: 10,
                label: "Tags",
                icon: "hash",
                capability: "taxonomy",
                position: 10,
                exact: false
            });
            Route.get("/tags/options", CmsController.tagOptions);
            Route.post("/tags/save", new SaveTagHandler());
            Route.post("/tags/{id}/delete", CmsController.deleteTag).whereNumber("id");
            Route.get("/themes/create", ThemeStudioController.create);
            Route.post("/themes/create", new SaveThemeDesignHandler(true));
            Route.get("/themes/{id}/design", ThemeStudioController.editor);
            Route.get("/themes/{id}/assets", ThemeAssetController.index);
            Route.post("/themes/{id}/assets", new UploadThemeImageHandler());
            Route.post("/themes/{id}/assets/{asset}/delete", ThemeAssetController.remove)
                .whereNumber("asset");
            Route.post("/themes/{id}/design", new SaveThemeDesignHandler());
            Route.post("/themes/{id}/design/data", new PreviewThemeSourcesHandler());
            Route.get("/themes/{id}/export", new ExportThemeDesignHandler());
            Route.post("/themes/{id}/export", new ExportThemeDesignHandler());
            Route.get("/themes/{id}/ai", ThemeAiController.connection);
            Route.post("/themes/{id}/ai/permissions", new SaveThemeAiPermissionsHandler());
            Route.websocket("/themes/{id}/ai/ws")
                .middleware([ThemeBrowserMcpMiddleware])
                .handler(new ThemeMcpWebSocket(true))
                .attribute("inertia.share", false);
            Route.post("/themes/{id}/ai", ThemeAiController.connection);
            Route.delete("/themes/{id}/ai", ThemeAiController.connection);
            Route.get("/themes/{id}/design/status", ThemeAiController.status);
            Route.get("/themes/{id}/design/snapshot", ThemeAiController.snapshot);
            Route.get("/themes/{id}/design/frame", ThemeStudioController.frame)
                .attribute("theme.preview.frame", true);
            for (kind in ["plugin", "theme"]) {
                var packageKind = kind;
                var prefix = kind == "plugin" ? "/plugins" : "/themes";
                Route.get(prefix, request -> PackageController.index(request, packageKind))
                    .attribute("cms.navigation", {
                        group: "Appearance",
                        groupPosition: 20,
                        label: kind == "theme" ? "Themes" : "Plugins",
                        icon: kind == "theme" ? "palette" : "puzzle",
                        capability: "extensions",
                        position: kind == "theme" ? 0 : 10
                    });
                Route.post(prefix + "/upload",
                    request -> PackageController.upload(request, packageKind));
                Route.post(prefix + "/install",
                    request -> PackageController.install(request, packageKind));
                Route.post(prefix + "/discard",
                    request -> PackageController.discard(request, packageKind));
                Route.get(prefix + "/{id}/settings",
                    request -> PackageController.settings(request, packageKind));
                Route.post(prefix + "/{id}/settings", new SavePackageSettingsHandler(packageKind));
                for (action in ["enable", "disable", "uninstall"]) {
                    var packageAction = action;
                    Route.post(prefix + "/{id}/" + action,
                        request -> PackageController.action(request, packageKind, packageAction));
                }
            }
            Route.get("/extension-assets/{id}/{generation}/{asset}",
                new ExtensionAssetHandler(true))
                .where("asset", ".+");
            Route.get("/themes/{id}/preview", request -> PackageController.preview(request));
            Route.get("/themes/{id}/preview/frame",
                request -> PackageController.previewContent(request, "/"))
                .attribute("theme.preview.frame", true);
            Route.get("/themes/{id}/preview/frame/{path}",
                request -> PackageController.previewContent(request, "/" + request.route("path")))
                .where("path", ".+")
                .attribute("theme.preview.frame", true);
            Route.get("/settings", AdminController.settings).attribute("cms.navigation", {
                group: "Administration",
                groupPosition: 30,
                label: "Settings",
                icon: "settings",
                capability: "settings",
                position: 20,
                exact: false
            });
            Route.get("/navigation", request -> ManagementController.navigation(request))
                .attribute("cms.navigation", {
                    group: "Organization",
                    groupPosition: 10,
                    label: "Navigation",
                    icon: "menu",
                    capability: "navigation",
                    position: 20,
                    exact: false
                });
            Route.get("/navigation/content", ContentOptions.published);
            Route.get("/navigation/regions", ManagementController.regionOptions);
            Route.post("/navigation/regions/save", new SaveNavigationRegionHandler());
            Route.post("/navigation/save", new SaveNavigationHandler());
            Route.post("/navigation/{id}/delete", ManagementController.deleteNavigation);
            Route.get("/team", request -> ManagementController.team(request))
                .attribute("cms.navigation", {
                    group: "Administration",
                    groupPosition: 30,
                    label: "Team",
                    icon: "users",
                    capability: "team",
                    position: 0,
                    exact: false
                });
            Route.post("/team/save", new SaveMemberHandler());
            Route.get("/roles", RoleController.index).attribute("cms.navigation", {
                group: "Administration",
                groupPosition: 30,
                label: "Roles",
                icon: "lock",
                capability: "roles",
                position: 5
            });
            Route.get("/roles/new", request -> RoleController.editor(request, true));
            Route.get("/roles/capabilities", RoleController.capabilities);
            Route.get("/roles/{key}/edit", request -> RoleController.editor(request));
            Route.post("/roles/create", new SaveRoleHandler());
            Route.post("/roles/{key}/save", new SaveRoleHandler());
            Route.post("/roles/{key}/delete", RoleController.remove);
            Route.get("/activity", ManagementController.activity).attribute("cms.navigation", {
                group: "Administration",
                groupPosition: 30,
                label: "Activity",
                icon: "clock",
                capability: "activity",
                position: 10,
                exact: false
            });
            Route.get("/account", request -> ManagementController.account(request))
                .attribute("cms.navigation", {
                    group: "Administration",
                    groupPosition: 30,
                    label: "Your account",
                    icon: "lock",
                    capability: "account",
                    position: 30,
                    exact: false
                });
            Route.post("/account", new SaveAccountHandler());
            Route.post("/settings", new SaveSettingsHandler());
            Route.post("/password", new ChangePasswordHandler());
        });
    }
}
