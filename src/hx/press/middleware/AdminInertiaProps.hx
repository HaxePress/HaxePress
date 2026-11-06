package hx.press.middleware;

import hx.well.middleware.AbstractMiddleware;
import hx.well.http.Request;
import hx.well.http.Response;
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
        var grants:Array<String> = [];
        if (admin != null) {
            grants = Roles.grants(admin.role);
            Inertia.share("mediaRules", MediaReferences.rules());
            current = {
                id: admin.id,
                name: admin.name,
                email: admin.email,
                role: admin.role,
                roleLabel: Roles.label(admin.role),
                capabilities: grants
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
            var pluginLinks = PluginRuntime.navigation("admin", grants.copy());
            Inertia.share("adminNavigation", AdminNavigation.groups(request, pluginLinks, grants));
            Inertia.share("pluginNavigation", {
                admin: pluginLinks,
                header: [],
                footer: []
            });
        }
        return next(request);
    }
}
