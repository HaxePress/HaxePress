package hx.press.model;

import hx.well.model.BaseModel;
import hx.well.model.BaseModelQuery;

@:table("navigation_regions")
class NavigationRegion extends BaseModel<NavigationRegion> {
    public static var query:BaseModelQuery<NavigationRegion>;

    @:primary @:visible @:field public var key:String = "";
    @:visible @:field public var name:String = "";
    @:visible @:field public var max_links:Int = 12;
    @:visible @:field public var enabled:Int = 1;
    @:visible @:field public var system:Int = 0;
}
