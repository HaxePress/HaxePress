package hx.press.model;

import hx.well.model.BaseModelQuery;
import hx.well.model.BaseModel;

@:connection("default")
@:table("login_attempts")
class LoginAttempt extends BaseModel<LoginAttempt> {
    public static var query:BaseModelQuery<LoginAttempt>;

    @:primary @:field public var key:String;
    @:field public var attempts:Int;
    @:field public var expires_at:Float;
}
