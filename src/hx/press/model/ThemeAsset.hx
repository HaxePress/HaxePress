package hx.press.model;

import hx.well.model.BaseModel;
import hx.well.model.BaseModelQuery;
import hx.press.database.DatabaseDate;

@:connection("default")
@:table("theme_assets")
class ThemeAsset extends BaseModel<ThemeAsset> {
    public static var query:BaseModelQuery<ThemeAsset>;

    @:primary @:visible @:field public var id:Int = 0;
    @:visible @:field public var theme_id:String = "";
    @:visible @:field public var filename:String = "";
    @:visible @:field public var title:String = "";
    @:visible @:field public var alt:String = "";
    @:visible @:field public var mime_type:String = "";
    @:visible @:field public var width:Int = 0;
    @:visible @:field public var height:Int = 0;
    @:visible @:field public var size:Int = 0;
    @:visible @:field public var sha256:String = "";
    @:field public var created_at:DatabaseDate;
}
