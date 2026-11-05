package hx.press.model;

import hx.well.model.BaseModel;
import hx.well.model.BaseModelQuery;

@:table("content_values")
class ContentValue extends BaseModel<ContentValue> {
    public static var query:BaseModelQuery<ContentValue>;

    @:primary @:visible @:field public var id:Int = 0;
    @:visible @:field public var content_id:Int = 0;
    @:visible @:field public var field_key:String = "";
    @:visible @:field public var value:String = "null";
    @:visible @:field public var value_text:String = "";
    @:visible @:field public var value_number:Float = 0;
}
