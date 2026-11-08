package fixtures;

import hx.well.model.BaseModel;
import hx.well.model.BaseModelQuery;

/** The View Count plugin's totals, which tests fill through the fixture process. **/
@:connection("default")
@:table("plugin_view_count_totals")
class ViewTotalRecord extends BaseModel<ViewTotalRecord> {
    public static var query:BaseModelQuery<ViewTotalRecord>;

    @:primary @:visible @:field public var id:Int = 0;
    @:visible @:field public var content_id:Int = 0;
    @:visible @:field public var views:Int = 0;
}
