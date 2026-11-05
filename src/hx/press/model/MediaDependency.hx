package hx.press.model;

import hx.well.model.BaseModel;
import hx.well.model.BaseModelQuery;

/** Owner data survives package deactivation and removal, so this has no package cascade. */
@:table("media_dependencies")
class MediaDependency extends BaseModel<MediaDependency> {
    public static var query:BaseModelQuery<MediaDependency>;

    @:primary @:visible @:field public var id:Int = 0;
    @:visible @:field public var media_id:Int = 0;
    @:visible @:field public var owner:String = "";
    @:visible @:field public var reference_key:String = "";
    @:visible @:field public var label:String = "";
}
