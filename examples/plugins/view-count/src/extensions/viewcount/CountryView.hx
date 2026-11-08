package extensions.viewcount;

import hx.press.plugins.PluginDatabase;
import hx.well.model.BaseModel;
import hx.well.model.BaseModelQuery;

/** How many counted views one content item has from one country. **/
@:table(PluginDatabase.table("view-count", "countries"))
class CountryView extends BaseModel<CountryView> {
    public static var query:BaseModelQuery<CountryView>;

    @:primary @:visible @:field public var id:Int;
    @:visible @:field public var content_id:Int;
    @:visible @:field public var country:String;
    @:visible @:field public var views:Int;
}
