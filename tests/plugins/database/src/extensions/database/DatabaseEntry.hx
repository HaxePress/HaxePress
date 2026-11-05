package extensions.database;

import hx.press.plugins.PluginDatabase;
import hx.press.database.DatabaseDate;
import hx.well.model.BaseModel;
import hx.well.model.BaseModelQuery;

@:table(PluginDatabase.table("database-test", "entries"))
class DatabaseEntry extends BaseModel<DatabaseEntry> {
    public static var query:BaseModelQuery<DatabaseEntry>;

    @:primary @:visible @:field public var id:Int;
    @:visible @:field public var key:String;
    @:visible @:field public var title:String;
    @:visible @:field public var rating:Int = 0;
    @:visible @:field public var content_id:Null<Int>;
    @:visible @:field public var created_at:DatabaseDate;
}
