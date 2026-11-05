package hx.press.model;

import hx.well.model.BaseModel;
import hx.well.model.BaseModelQuery;

/** Persistent model declarations can be checked without loading plugin code. */
@:table("media_dependency_sources")
class MediaDependencySource extends BaseModel<MediaDependencySource> {
    public static var query:BaseModelQuery<MediaDependencySource>;

    @:primary @:visible @:field public var key:String = "";
    @:visible @:field public var owner:String = "";
    @:visible @:field public var connection_name:String = "default";
    @:visible @:field public var table_name:String = "";
    @:visible @:field public var column_name:String = "";
    @:visible @:field public var mode:String = "id";
    @:visible @:field public var label:String = "";
}
