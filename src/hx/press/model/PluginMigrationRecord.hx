package hx.press.model;

import hx.well.model.BaseModelQuery;
import hx.well.model.BaseModel;
import hx.press.database.DatabaseDate;

@:table("plugin_migrations")
class PluginMigrationRecord extends BaseModel<PluginMigrationRecord> {
    public static var query:BaseModelQuery<PluginMigrationRecord>;

    @:primary @:visible @:field public var id:String;
    @:visible @:field public var plugin_id:String;
    @:visible @:field public var name:String;
    @:visible @:field public var applied_at:DatabaseDate;
}
