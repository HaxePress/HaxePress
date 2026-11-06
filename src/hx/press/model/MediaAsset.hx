package hx.press.model;

import hx.well.model.BaseModelQuery;
import hx.well.model.BaseModel;
import hx.press.database.DatabaseDate;

@:connection("default")
@:table("media_assets")
class MediaAsset extends BaseModel<MediaAsset> {
    public static var query:BaseModelQuery<MediaAsset>;

    @:primary @:visible @:field public var id:Int = 0;
    @:visible @:field public var filename:String = "";
    @:visible @:field public var title:String = "";
    @:visible @:field public var alt:String = "";
    @:visible @:field public var mime_type:String = "";
    @:visible @:field public var width:Int = 0;
    @:visible @:field public var height:Int = 0;
    @:visible @:field public var size:Int = 0;
    @:visible @:field public var created_at:DatabaseDate = "";
    @:visible @:field public var updated_at:DatabaseDate = "";

    /** When the image moved to the trash, in milliseconds since the epoch; 0 outside it. **/
    @:visible @:field public var trashed_epoch:Float = 0;
}
