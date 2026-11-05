package hx.press.model;

import hx.well.model.BaseModelQuery;
import hx.well.model.BaseModel;
import hx.press.database.DatabaseDate;

@:table("plugin_values")
class PluginValue extends BaseModel<PluginValue> {
    public static var query:BaseModelQuery<PluginValue>;

    @:primary @:visible @:field public var id:Int;
    @:visible @:field public var plugin_id:String;
    @:visible @:field public var scope:String;
    @:visible @:field public var key:String;
    @:visible @:field public var value:String;
    @:visible @:field public var updated_at:DatabaseDate;
}
