package hx.press.model;

import hx.well.model.BaseModel;
import hx.well.model.BaseModelQuery;

@:connection("default")
@:table("theme_ai_permissions")
class ThemeAiPermission extends BaseModel<ThemeAiPermission> {
    public static var query:BaseModelQuery<ThemeAiPermission>;

    @:primary @:field public var id:String = "";
    @:field public var theme_id:String = "";
    @:field public var admin_id:Int = 0;
    @:visible @:field public var allow_read:Int = 1;
    @:visible @:field public var allow_edit:Int = 1;
    @:visible @:field public var allow_media:Int = 1;
}
