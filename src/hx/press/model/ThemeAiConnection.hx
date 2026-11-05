package hx.press.model;

import hx.well.model.BaseModel;
import hx.well.model.BaseModelQuery;

@:connection("default")
@:table("theme_ai_connections")
class ThemeAiConnection extends BaseModel<ThemeAiConnection> {
    public static var query:BaseModelQuery<ThemeAiConnection>;

    @:primary @:field public var id:String = "";
    @:field public var theme_id:String = "";
    @:field public var admin_id:Int = 0;
    @:field public var token_hash:String = "";
    @:field public var auth_version:String = "";
    @:visible @:field public var expires_epoch:Float = 0;
}
