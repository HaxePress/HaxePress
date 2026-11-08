package extensions.viewcount;

import hx.press.plugins.PluginDatabase;
import hx.well.model.BaseModel;
import hx.well.model.BaseModelQuery;

/** How many counted views one content item has. **/
@:table(PluginDatabase.table("view-count", "totals"))
class ViewTotal extends BaseModel<ViewTotal> {
    public static var query:BaseModelQuery<ViewTotal>;

    @:primary @:visible @:field public var id:Int;
    @:visible @:field public var content_id:Int;
    @:visible @:field public var views:Int;
}
