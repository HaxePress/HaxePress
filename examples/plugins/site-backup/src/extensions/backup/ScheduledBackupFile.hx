package extensions.backup;

import hx.well.model.BaseModel;
import hx.well.model.BaseModelQuery;

/** A saved backup of a schedule. The table keeps its name so existing files stay listed. **/
@:connection("default")
@:table("scheduled_backup_files")
class ScheduledBackupFile extends BaseModel<ScheduledBackupFile> {
    public static var query:BaseModelQuery<ScheduledBackupFile>;

    @:primary @:visible @:field public var id:String = "";
    @:visible @:field public var schedule_id:String = "";
    @:visible @:field public var created_epoch:Float = 0;
    @:visible @:field public var cms_version:String = "";
    @:visible @:field public var encrypted:Int = 0;
    @:visible @:field public var size:Int = 0;
    @:visible @:field public var md5:String = "";
}
