package hx.press.model;

import hx.well.model.BaseModel;
import hx.well.model.BaseModelQuery;

/**
    A text the site shows: a message of the CMS, a theme or a plugin, or a
    text of the site itself such as a category name. `source` holds its
    wording in `language`; a plural text keeps `{"one", "other"}` as JSON.
**/
@:connection("default")
@:table("translation_texts")
class TranslationText extends BaseModel<TranslationText> {
    public static var query:BaseModelQuery<TranslationText>;

    @:primary @:visible @:field public var id:Int = 0;
    @:visible @:field public var namespace:String = "";
    @:visible @:field public var key:String = "";
    @:visible @:field public var key_hash:String = "";
    @:visible @:field public var origin:String = "";
    @:visible @:field public var audience:String = "site";
    @:visible @:field public var source:String = "";
    @:visible @:field public var plural:Int = 0;
    @:visible @:field public var language:String = "en";
    @:visible @:field public var unused:Int = 0;
    @:visible @:field public var updated_epoch:Float = 0;
}
