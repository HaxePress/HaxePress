package hx.press.model;

import hx.well.model.BaseModelQuery;
import hx.well.model.BaseModel;

@:connection("default")
@:table("settings")
class Setting extends BaseModel<Setting> {
    public static var query:BaseModelQuery<Setting>;

    @:primary @:field public var key:String;
    @:field public var value:String;
}
