package hx.press.model;

import hx.well.model.BaseModel;
import hx.well.model.BaseModelQuery;

@:table("role_grants")
class RoleGrant extends BaseModel<RoleGrant> {
    public static var query:BaseModelQuery<RoleGrant>;

    @:primary @:visible @:field public var id:Int = 0;
    @:visible @:field public var role_key:String = "";
    @:visible @:field public var capability:String = "";
}
