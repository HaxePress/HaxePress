package hx.press.routes;

import hx.press.ContentController;
import hx.press.ContentWorkflow;
import hx.press.ai.AdminMcpPolicy;
import hx.press.handler.admin.content.SaveContentHandler;
import hx.press.handler.admin.content.SaveWorkingCopyHandler;
import hx.press.handler.admin.content.DeleteContentHandler;
import hx.well.http.Request;
import hx.well.route.Route;

/** Every collection uses the same guarded editor, history and publishing endpoints. */
using hx.well.tools.RouteElementTools;

class CollectionRoutes {
    public static function register(prefix:String, resolve:Request->String):Void {
        Route.get(prefix, request -> ContentController.index(request, resolve(request)));
        Route.get('${prefix}/new',
            request -> ContentController.newDocument(request, resolve(request)));
        Route.get('${prefix}/{id}/edit',
            request -> ContentController.edit(request, resolve(request)))
            .whereNumber("id");
        Route.post('${prefix}/save', new SaveContentHandler(resolve));
        Route.post('${prefix}/preview',
            request -> ContentController.preview(request, resolve(request)))
            .attribute("content.preview", true);
        Route.post('${prefix}/{id}/delete', new DeleteContentHandler(resolve))
            .whereNumber("id")
            .attribute(AdminMcpPolicy.PEOPLE_ONLY, true);
        Route.post('${prefix}/working-copy', new SaveWorkingCopyHandler(resolve));
        Route.post('${prefix}/{id}/discard-working',
            request -> ContentController.discardWorking(request, resolve(request)));
        Route.get('${prefix}/{id}/history',
            request -> ContentController.history(request, resolve(request)));
        Route.get('${prefix}/{id}/history/{revision}',
            request -> ContentController.revision(request, resolve(request)));
        Route.post('${prefix}/{id}/history/{revision}/restore',
            request -> ContentController.revision(request, resolve(request), true));
        Route.post('${prefix}/{id}/trash',
            request -> ContentWorkflow.change(request, resolve(request), false));
        Route.post('${prefix}/{id}/restore',
            request -> ContentWorkflow.change(request, resolve(request), true));
        Route.post('${prefix}/{id}/permanent-delete', new DeleteContentHandler(resolve, true))
            .attribute(AdminMcpPolicy.PEOPLE_ONLY, true);
    }
}
