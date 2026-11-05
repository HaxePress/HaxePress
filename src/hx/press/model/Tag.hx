package hx.press.model;

import hx.well.model.BaseModelQuery;
import hx.well.model.BaseModel;
import hx.press.database.DatabaseDate;

@:connection("default")
@:table("tags")
class Tag extends BaseModel<Tag> {
    public static var query:BaseModelQuery<Tag>;

    @:primary @:visible @:field public var id:Int = 0;
    @:visible @:field public var name:String = "";
    @:visible @:field public var name_key:String = "";
    @:visible @:field public var slug:String = "";
    @:visible @:field public var description:String = "";
    @:visible @:field public var created_at:DatabaseDate = "";
    @:visible @:field public var updated_at:DatabaseDate = "";
}
