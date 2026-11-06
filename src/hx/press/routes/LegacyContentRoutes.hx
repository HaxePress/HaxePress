package hx.press.routes;

import hx.well.http.Request;
import hx.well.http.ResponseBuilder;
import hx.well.route.Route;

/** Existing public links retain their destination after the CMS naming migration. */
class LegacyContentRoutes {
    public static function registerAdmin():Void {
        Route.get("/posts",
            (request:Request) -> ResponseBuilder.asRedirect('/admin/content${query(request)}',
                301));
        Route.get("/posts/new",
            (request:Request) -> ResponseBuilder.asRedirect('/admin/content/new${query(request)}',
                301));
        Route.get("/posts/{id}/edit",
            (request:Request) ->
                ResponseBuilder.asRedirect('/admin/content/${StringTools.urlEncode(request.route("id"))}/edit${query(request)}',
                301));
    }

    static function query(request:Request):String {
        var values = [
            for (key => value in request.queries)
                '${StringTools.urlEncode(key)}=${StringTools.urlEncode(value)}'
        ];
        return values.length == 0 ? "" : '?${values.join("&")}';
    }

    public static function register():Void {
        Route.get("/journal",
            (request:Request) -> ResponseBuilder.asRedirect('/content${query(request)}', 301));
        Route.get("/story/{slug}",
            (request:Request) ->
                ResponseBuilder.asRedirect('/content/${StringTools.urlEncode(request.route("slug"))}${query(request)}',
                    301));
        Route.get("/p/{slug}",
            (request:Request) ->
                ResponseBuilder.asRedirect('/pages/${StringTools.urlEncode(request.route("slug"))}${query(request)}',
                    301));
        Route.get("/tag/{slug}",
            (request:Request) ->
                ResponseBuilder.asRedirect('/tags/${StringTools.urlEncode(request.route("slug"))}${query(request)}',
                    301));
    }
}
