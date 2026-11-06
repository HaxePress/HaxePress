package hx.press.model;

import hx.well.model.BaseModel;
import hx.well.model.BaseModelQuery;

@:connection("default")
@:table("scheduled_jobs")
class ScheduledJob extends BaseModel<ScheduledJob> {
    public static var query:BaseModelQuery<ScheduledJob>;

    @:primary @:visible @:field public var id:String = "";
    @:visible @:field public var plugin_id:Null<String> = null;
    @:visible @:field public var job_key:String = "";
    @:visible @:field public var payload:String = "{}";
    @:visible @:field public var interval_seconds:Int = 0;
    @:visible @:field public var enabled:Int = 1;
    @:visible @:field public var next_epoch:Float = 0;
    @:visible @:field public var last_epoch:Float = 0;
    @:visible @:field public var last_error:String = "";
    @:visible @:field public var lease_until:Float = 0;
    @:visible @:field public var run_token:String = "";
}
