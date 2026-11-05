package hx.press.model;

import hx.well.model.BaseModelQuery;
import hx.well.model.BaseModel;

@:connection("default")
@:table("package_hooks")
class PackageHook extends BaseModel<PackageHook> {
    public static var query:BaseModelQuery<PackageHook>;

    @:primary @:visible @:field public var id:Int = 0;
    @:visible @:field public var package_id:String = "";
    @:visible @:field public var event:String = "";
}
