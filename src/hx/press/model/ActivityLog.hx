package hx.press.model;

import hx.well.model.BaseModelQuery;
import hx.well.model.BaseModel;
import hx.press.database.DatabaseDate;

@:connection("default")
@:table("activity_logs")
class ActivityLog extends BaseModel<ActivityLog> {
    public static var query:BaseModelQuery<ActivityLog>;

    @:primary @:visible @:field public var id:Int = 0;
    @:visible @:field public var user_id:Int = 0;
    @:visible @:field public var actor:String = "";
    @:visible @:field public var action:String = "";
    @:visible @:field public var entity:String = "";
    @:visible @:field public var entity_id:Int = 0;
    @:visible @:field public var label:String = "";
    @:visible @:field public var created_at:DatabaseDate = "";
}
