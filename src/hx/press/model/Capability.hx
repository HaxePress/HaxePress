package hx.press.model;

import hx.well.model.BaseModel;
import hx.well.model.BaseModelQuery;

@:table("capabilities")
class Capability extends BaseModel<Capability> {
    public static var query:BaseModelQuery<Capability>;

    @:primary @:visible @:field public var key:String = "";
    @:visible @:field public var name:String = "";
    @:visible @:field public var group_name:String = "";
    @:visible @:field public var owner:String = "";
}
