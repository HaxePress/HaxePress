package extensions.mediatest;

import hx.press.plugins.PluginDatabase;
import hx.well.model.BaseModel;
import hx.well.model.BaseModelQuery;

@:table(PluginDatabase.table("media-test", "attachments"))
class MediaAttachment extends BaseModel<MediaAttachment> {
    public static var query:BaseModelQuery<MediaAttachment>;

    @:primary @:visible @:field public var id:Int = 0;
    @:visible @:field public var key:String = "";
    @:visible @:field public var media_id:Int = 0;
}
