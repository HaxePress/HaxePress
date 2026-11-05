package hx.press.model;

import hx.well.model.BaseModelQuery;
import hx.well.model.BaseModel;

@:connection("default")
@:table("package_uploads")
class PackageUpload extends BaseModel<PackageUpload> {
    public static var query:BaseModelQuery<PackageUpload>;

    @:primary @:visible @:field public var key:String = "";
    @:visible @:field public var user_id:Int = 0;
    @:visible @:field public var kind:String = "plugin";
    @:visible @:field public var directory:String = "";
    @:visible @:field public var manifest:String = "{}";
    @:visible @:field public var expires_epoch:Float = 0;
}
