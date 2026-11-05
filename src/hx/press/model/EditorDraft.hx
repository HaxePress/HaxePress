package hx.press.model;

import hx.well.model.BaseModelQuery;
import hx.well.model.BaseModel;
import hx.press.database.DatabaseDate;

@:connection("default")
@:table("editor_drafts")
class EditorDraft extends BaseModel<EditorDraft> {
    public static var query:BaseModelQuery<EditorDraft>;

    @:primary @:visible @:field public var key:String = "";
    @:visible @:field public var document_id:Int = 0;
    @:visible @:field public var user_id:Int = 0;
    @:visible @:field public var kind:String = "entry";
    @:visible @:field public var title:String = "";
    @:visible @:field public var payload:String = "";
    @:visible @:field public var version:Int = 0;
    @:visible @:field public var base_version:Int = 0;
    @:visible @:field public var expires_epoch:Float = 0;
    @:visible @:field public var updated_at:DatabaseDate = "";
}
