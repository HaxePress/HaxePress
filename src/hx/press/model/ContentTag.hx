package hx.press.model;

import hx.well.model.BaseModelQuery;
import hx.well.model.BaseModel;

@:connection("default")
@:table("content_tags")
class ContentTag extends BaseModel<ContentTag> {
    public static var query:BaseModelQuery<ContentTag>;

    @:primary @:visible @:field public var id:Int = 0;
    @:visible @:field public var content_id:Int = 0;
    @:visible @:field public var tag_id:Int = 0;
}
