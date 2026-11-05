package hx.press.model;

import hx.well.model.BaseModel;
import hx.well.model.BaseModelQuery;

@:table("roles")
class Role extends BaseModel<Role> {
    public static var query:BaseModelQuery<Role>;

    @:primary @:visible @:field public var key:String = "";
    @:visible @:field public var name:String = "";
    @:visible @:field public var description:String = "";
    @:visible @:field public var enabled:Int = 1;
    @:visible @:field public var system:Int = 0;
    @:visible @:field public var owner:String = "";
}
