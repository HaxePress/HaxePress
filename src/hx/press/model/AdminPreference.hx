package hx.press.model;

import hx.well.model.BaseModel;
import hx.well.model.BaseModelQuery;

/** A choice an administrator made for their own view of the admin, such as list columns. */
@:connection("default")
@:table("admin_preferences")
class AdminPreference extends BaseModel<AdminPreference> {
    public static var query:BaseModelQuery<AdminPreference>;

    @:primary @:field public var id:Int = 0;
    @:field public var admin_id:Int = 0;
    @:field public var preference:String = "";
    @:field public var value:String = "";
    @:field public var updated_epoch:Float = 0;
}
