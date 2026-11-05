package hx.press.model;

import hx.press.database.DatabaseDate;
import hx.well.model.BaseModel;
import hx.well.model.BaseModelQuery;

@:table("content_types")
class ContentType extends BaseModel<ContentType> {
    public static var query:BaseModelQuery<ContentType>;

    @:primary @:visible @:field public var key:String = "";
    @:visible @:field public var name:String = "";
    @:visible @:field public var singular:String = "";
    @:visible @:field public var description:String = "";
    @:visible @:field public var icon:String = "file";
    @:visible @:field public var admin_path:String = "";
    @:visible @:field public var public_path:String = "";
    @:visible @:field public var public_visible:Int = 1;
    @:visible @:field public var has_archive:Int = 1;
    @:visible @:field public var enabled:Int = 1;
    @:visible @:field public var system:Int = 0;
    @:visible @:field public var owner:String = "";
    @:visible @:field public var capability:String = "content";
    @:visible @:field public var position:Int = 10;
    @:visible @:field public var template:String = "ContentDetail";
    @:visible @:field public var archive_template:String = "ContentIndex";
    @:visible @:field public var features:String = "[]";
    @:visible @:field public var fields:String = "[]";
    @:visible @:field public var labels:String = "{}";
    @:visible @:field public var minimum_title_length:Int = 1;
    @:visible @:field public var minimum_content_length:Int = 0;
    @:visible @:field public var minimum_excerpt_length:Int = 0;
    @:visible @:field public var created_at:DatabaseDate = "";
    @:visible @:field public var updated_at:DatabaseDate = "";
}
