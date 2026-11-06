package hx.press.model;

import hx.well.model.BaseModel;
import hx.well.model.BaseModelQuery;

@:connection("default")
@:table("image_uploads")
class ImageUpload extends BaseModel<ImageUpload> {
    public static var query:BaseModelQuery<ImageUpload>;

    @:primary @:visible @:field public var key:String = "";
    @:visible @:field public var user_id:Int = 0;
    @:visible @:field public var owner_hash:String = "";
    @:visible @:field public var theme_id:String = "";
    @:visible @:field public var label:String = "";
    @:visible @:field public var sha256:String = "";
    @:visible @:field public var size:Int = 0;
    @:visible @:field public var expires_epoch:Float = 0;
}
