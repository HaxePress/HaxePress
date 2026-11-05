package hx.press.model;

import hx.well.model.BaseModelQuery;
import hx.well.model.BaseModel;
import hx.press.database.DatabaseDate;

@:connection("default")
@:table("subscribers")
class Subscriber extends BaseModel<Subscriber> {
    public static var query:BaseModelQuery<Subscriber>;

    @:primary @:visible @:field public var id:Int;
    @:visible @:field public var email:String;
    @:visible @:field public var created_at:DatabaseDate;
}
