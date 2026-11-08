package hx.press.middleware;

import hx.press.content.ContentViews;
import hx.press.content.ContentViewBuffer;
import hx.well.http.Request;
import hx.well.http.Response;
import hx.well.middleware.AbstractMiddleware;

/**
    Counts a visitor's view of published content once the response is
    complete. The count is added in `dispose`, which HxWell calls after
    sending the response, and reaches plugins with the next minute's
    `content.viewed` hook.
**/
class ContentViewMiddleware extends AbstractMiddleware {
    var id = 0;
    var type = "";
    var country = "";

    public function handle(request:Request, next:Request->Null<Response>):Null<Response> {
        var response = next(request);
        if (ContentViews.content(request) == null) {
            return response;
        }
        id = ContentViews.counted(request, response);
        if (id > 0) {
            var shown:Dynamic = ContentViews.content(request);
            type = shown.type;
            country = ContentViews.country(request);
        }
        return response;
    }

    public override function dispose():Void {
        if (id > 0) {
            var counted = id;
            id = 0;
            try {
                ContentViewBuffer.add(counted, type, country);
            } catch (error:Dynamic) {
                trace('A content view could not be counted: ${Std.string(error)}');
            }
        }
        super.dispose();
    }
}
