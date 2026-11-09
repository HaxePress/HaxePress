package hx.press.model;

import hx.well.model.BaseModel;
import hx.well.model.BaseModelQuery;

/**
    A language the site publishes in. Exactly one is the default, which has
    no address prefix; the others are served under `/{code}/`. A disabled
    language keeps its content and translations but is not public.
**/
@:connection("default")
@:table("languages")
class Language extends BaseModel<Language> {
    public static var query:BaseModelQuery<Language>;

    @:primary @:visible @:field public var code:String = "";
    @:visible @:field public var name:String = "";
    @:visible @:field public var direction:String = "ltr";
    @:visible @:field public var position:Int = 0;
    @:visible @:field public var is_default:Int = 0;
    @:visible @:field public var enabled:Int = 1;
    @:visible @:field public var home_page_id:Int = 0;
    @:visible @:field public var updated_epoch:Float = 0;
}
