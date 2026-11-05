package hx.press.model;

import hx.well.model.BaseModel;
import hx.well.model.BaseModelQuery;
import hx.press.database.DatabaseDate;

@:connection("default")
@:table("theme_designs")
class ThemeDesign extends BaseModel<ThemeDesign> {
    public static var query:BaseModelQuery<ThemeDesign>;

    @:primary @:visible @:field public var id:String = "";
    @:visible @:field public var draft:String = "{}";
    @:visible @:field public var published:String = "";
    @:visible @:field public var version:Int = 1;
    @:visible @:field public var published_version:Int = 0;
    @:visible @:field public var updated_at:DatabaseDate = "";
}
