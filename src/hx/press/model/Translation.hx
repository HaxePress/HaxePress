package hx.press.model;

import hx.well.model.BaseModel;
import hx.well.model.BaseModelQuery;

/**
    A text in one language. `shipped` copies the translation its theme or
    plugin ships, and `value` holds the one made on this site, which wins.
    A row with neither does not exist: the text is missing in that language.
**/
@:connection("default")
@:table("translations")
class Translation extends BaseModel<Translation> {
    public static var query:BaseModelQuery<Translation>;

    @:primary @:visible @:field public var id:Int = 0;
    @:visible @:field public var text_id:Int = 0;
    @:visible @:field public var language:String = "";
    @:visible @:field public var value:String = "";
    @:visible @:field public var shipped:String = "";
    @:visible @:field public var outdated:Int = 0;
    @:visible @:field public var updated_by:Int = 0;
    @:visible @:field public var updated_epoch:Float = 0;
}
