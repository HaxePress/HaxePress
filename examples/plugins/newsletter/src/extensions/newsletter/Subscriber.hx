package extensions.newsletter;

import hx.press.database.DatabaseDate;
import hx.well.model.BaseModel;
import hx.well.model.BaseModelQuery;

// Retain the original table name so existing subscriptions survive the upgrade.
@:table("subscribers")
class Subscriber extends BaseModel<Subscriber> {
    public static var query:BaseModelQuery<Subscriber>;

    @:primary @:visible @:field public var id:Int;
    @:visible @:field public var email:String;
    @:visible @:field public var created_at:DatabaseDate;
}
