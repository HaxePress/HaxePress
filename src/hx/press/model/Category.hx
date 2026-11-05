package hx.press.model;

import hx.well.model.BaseModelQuery;
import hx.well.model.BaseModel;
import hx.press.database.DatabaseDate;

@:connection("default")
@:table("categories")
class Category extends BaseModel<Category> {
    public static var query:BaseModelQuery<Category>;

    @:primary @:visible @:field public var id:Int;
    @:visible @:field public var name:String;
    @:field public var name_key:String;
    @:visible @:field public var created_at:DatabaseDate;
    @:visible @:field public var updated_at:DatabaseDate;
}
