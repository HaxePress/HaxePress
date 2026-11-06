package hx.press.model;

import hx.well.model.BaseModel;
import hx.well.model.BaseModelQuery;

@:connection("default")
@:table("scheduled_backup_files")
class ScheduledBackup extends BaseModel<ScheduledBackup> {
    public static var query:BaseModelQuery<ScheduledBackup>;

    @:primary @:visible @:field public var id:String = "";
    @:visible @:field public var schedule_id:String = "";
    @:visible @:field public var created_epoch:Float = 0;
    @:visible @:field public var cms_version:String = "";
    @:visible @:field public var encrypted:Int = 0;
    @:visible @:field public var size:Int = 0;
    @:visible @:field public var md5:String = "";
}
