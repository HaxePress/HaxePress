package extensions.viewcount;

import hx.press.content.ContentViews;
import hx.well.http.Request;
import hx.well.http.Response;
import hx.well.middleware.AbstractMiddleware;

/**
    Counts a visitor's view of published content once the response is
    complete. The view is added in `dispose`, which HxWell calls after
    sending the response, and reaches the database with the plugin's next
    flush.
**/
class ViewCountMiddleware extends AbstractMiddleware {
    var id = 0;
    var type = "";
    var country = "";

    public function handle(request:Request, next:Request->Null<Response>):Null<Response> {
        var response = next(request);
        var view:Dynamic = ViewRules.counted(request, response);
        if (view != null) {
            id = view.id;
            type = view.type;
            country = ContentViews.country(request) ?? CountryViewData.UNKNOWN;
        }
        return response;
    }

    public override function dispose():Void {
        if (id > 0) {
            var counted = id;
            id = 0;
            try {
                ViewBuffer.add(counted, type, country);
            } catch (error:Dynamic) {
                trace('A content view could not be counted: ${Std.string(error)}');
            }
        }
        super.dispose();
    }
}
