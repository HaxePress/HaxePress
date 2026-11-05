package hx.press.model;

import hx.well.model.BaseModel;
import hx.well.model.BaseModelQuery;

@:table("content_type_paths")
class ContentTypePath extends BaseModel<ContentTypePath> {
    public static var query:BaseModelQuery<ContentTypePath>;

    @:primary @:visible @:field public var path:String = "";
    @:visible @:field public var type_key:String = "";
}
