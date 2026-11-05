package hx.press.model;

import hx.well.model.BaseModelQuery;
import hx.well.model.BaseModel;
import hx.press.database.DatabaseDate;

@:connection("default")
@:table("menu_links")
class MenuLink extends BaseModel<MenuLink> {
    public static var query:BaseModelQuery<MenuLink>;

    @:primary @:visible @:field public var id:Int = 0;
    @:visible @:field public var location:String = "header";
    @:visible @:field public var label:String = "";
    @:visible @:field public var url:String = "";
    @:visible @:field public var position:Int = 0;
    @:visible @:field public var new_tab:Int = 0;
    @:visible @:field public var content_id:Int = 0;
    @:visible @:field public var collection_key:String = "";
    @:visible @:field public var created_at:DatabaseDate = "";
    @:visible @:field public var updated_at:DatabaseDate = "";
}
