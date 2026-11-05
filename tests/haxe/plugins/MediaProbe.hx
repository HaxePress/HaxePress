package plugins;

import hx.well.model.BaseModel;
import hx.well.model.BaseModelQuery;

@:table("media_dependency_probe")
class MediaProbe extends BaseModel<MediaProbe> {
    public static var query:BaseModelQuery<MediaProbe>;

    @:primary @:visible @:field public var id:Int = 0;
    @:visible @:field public var media_id:Int = 0;
    @:visible @:field public var source:String = "";
}
