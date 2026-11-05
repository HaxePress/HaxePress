package hx.press.model;

import hx.well.model.BaseModelQuery;
import hx.well.model.BaseModel;
import hx.press.database.DatabaseDate;

@:connection("default")
@:table("content_revisions")
class ContentRevision extends BaseModel<ContentRevision> {
    public static var query:BaseModelQuery<ContentRevision>;

    @:primary @:visible @:field public var id:Int = 0;
    @:visible @:field public var document_id:Int = 0;
    @:visible @:field public var version:Int = 1;
    @:visible @:field public var title:String = "";
    @:visible @:field public var snapshot:String = "";
    @:visible @:field public var author_id:Int = 0;
    @:visible @:field public var created_at:DatabaseDate = "";
}
