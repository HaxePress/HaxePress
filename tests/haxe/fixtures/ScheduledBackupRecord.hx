package fixtures;

import hx.well.model.BaseModel;
import hx.well.model.BaseModelQuery;

/** The backup plugin's saved schedule files, read by tests through the fixture process. **/
@:connection("default")
@:table("scheduled_backup_files")
class ScheduledBackupRecord extends BaseModel<ScheduledBackupRecord> {
    public static var query:BaseModelQuery<ScheduledBackupRecord>;

    @:primary @:visible @:field public var id:String = "";
    @:visible @:field public var schedule_id:String = "";
    @:visible @:field public var created_epoch:Float = 0;
    @:visible @:field public var cms_version:String = "";
    @:visible @:field public var encrypted:Int = 0;
    @:visible @:field public var size:Int = 0;
    @:visible @:field public var md5:String = "";
}
