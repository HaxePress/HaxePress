package hx.press.middleware;

import hx.well.middleware.AbstractMiddleware;
import hx.well.http.Request;
import hx.well.http.Response;
import hx.well.http.RequestStatic.auth;
import hx.well.facades.Inertia;
import hx.press.CmsAccess;
import hx.press.plugins.PluginHealth;
import hx.press.plugins.PluginRuntime;
import hx.press.AdminNavigation;
import hx.press.media.MediaReferences;
import hx.press.access.Roles;
import hx.well.middleware.CsrfMiddleware;

class AdminInertiaProps extends AbstractMiddleware {
    public function handle(request:Request, next:Request->Null<Response>):Null<Response> {
        var current:Dynamic = null;
        var admin = CmsAccess.current();
        if (admin != null) {
            Inertia.share("mediaRules", MediaReferences.rules());
            current = {
                id: admin.id,
                name: admin.name,
                email: admin.email,
                role: admin.role,
                roleLabel: Roles.find(admin.role).name,
                capabilities: CmsAccess.capabilities(admin.role)
            };
        }
        Inertia.share("auth", current == null ? null : {admin: current});
        Inertia.share("csrfToken", request.session.get(CsrfMiddleware.TOKEN_KEY));
        var flashed = Inertia.getFlashed(request);
        for (key => value in flashed) {
            Inertia.share(key, value);
        }
        Inertia.share("pluginRestartRequired", PluginHealth.restartRequired);
        if (admin != null) {
            var pluginLinks = PluginRuntime.navigation("admin", CmsAccess.capabilities(admin.role));
            Inertia.share("adminNavigation", AdminNavigation.groups(request, pluginLinks));
            Inertia.share("pluginNavigation", {
                admin: pluginLinks,
                header: [],
                footer: []
            });
        }
        return next(request);
    }
}
