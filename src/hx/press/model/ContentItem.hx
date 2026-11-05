package hx.press.model;

import hx.well.model.BaseModelQuery;
import hx.well.model.BaseModel;
import hx.press.database.DatabaseDate;

@:connection("default")
@:table("content_items")
class ContentItem extends BaseModel<ContentItem> {
    public static var query:BaseModelQuery<ContentItem>;

    @:primary @:visible @:field public var id:Int = 0;
    @:visible @:field public var title:String = "";
    @:visible @:field public var slug:String = "";
    @:visible @:field public var excerpt:String = "";
    @:visible @:field public var content:String = "";
    @:visible @:field public var category:String = "";
    @:visible @:field public var image:String = "";
    @:visible @:field public var image_alt:String = "";
    @:visible @:field public var status:String = "draft";
    @:visible @:field public var content_type:String = "entry";
    @:visible @:field public var version:Int = 1;
    @:visible @:field public var author_id:Int = 0;
    @:visible @:field public var seo_title:String = "";
    @:visible @:field public var seo_description:String = "";
    @:visible @:field public var scheduled_epoch:Float = 0;
    @:visible @:field public var previous_status:String = "draft";
    @:visible @:field public var featured:Int = 0;

    @:visible @:field public var reading_minutes:Int = 1;
    @:visible @:field public var published_at:Null<DatabaseDate> = null;
    @:visible @:field public var created_at:DatabaseDate = "";
    @:visible @:field public var updated_at:DatabaseDate = "";
}
