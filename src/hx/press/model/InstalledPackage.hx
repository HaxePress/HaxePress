package hx.press.model;

import hx.well.model.BaseModelQuery;
import hx.well.model.BaseModel;
import hx.press.database.DatabaseDate;

@:connection("default")
@:table("cms_packages")
class InstalledPackage extends BaseModel<InstalledPackage> {
    public static var query:BaseModelQuery<InstalledPackage>;

    @:primary @:visible @:field public var id:String = "";
    @:visible @:field public var kind:String = "plugin";
    @:visible @:field public var plugin_id:Null<String> = null;
    @:visible @:field public var slug:String = "";
    @:visible @:field public var name:String = "";
    @:visible @:field public var name_key:String = "";
    @:visible @:field public var version:String = "";
    @:visible @:field public var description:String = "";
    @:visible @:field public var author:String = "";
    @:visible @:field public var directory:String = "";
    @:visible @:field public var manifest:String = "{}";
    @:visible @:field public var last_error:String = "";
    @:visible @:field public var restart_required:Int = 0;
    @:visible @:field public var enabled:Int = 0;
    @:visible @:field public var setting_count:Int = 0;
    @:visible @:field public var settings:String = "{}";
    @:visible @:field public var installed_at:DatabaseDate = "";
    @:visible @:field public var updated_at:DatabaseDate = "";
}
