package hx.press.view.types.admin;

@:well.view
typedef AdminLanguageView = {
    var code:String;
    var name:String;
    var direction:String;
    var segment:String;

    /** The address prefix of the language, such as `/` or `/de/`. **/
    var address:String;

    var isDefault:Bool;
    var enabled:Bool;
    var homePageId:Int;
    var homeTitle:String;
    var moveUp:String;
    var moveDown:String;
}

@:well.view
typedef AdminLanguageFormView = {
    var originalCode:String;
    var code:String;
    var name:String;
    var direction:String;
    var enabled:Bool;
    var homePageId:Int;
}

@:well.view
typedef AdminLanguageSuggestionView = {
    var code:String;
    var name:String;
}

@:well.view
typedef AdminTranslationFilterView = {
    var language:String;
    var source:String;
    var status:String;
    var audience:String;
    var query:String;
}

@:well.view
typedef AdminTranslationLanguageView = {
    var code:String;
    var name:String;
    var isDefault:Bool;
    var enabled:Bool;
    var total:Int;
    var translated:Int;
    var edited:Int;
    var review:Int;
    var missing:Int;
    var percent:Int;
    var href:String;
}

@:well.view
typedef AdminTranslationSourceView = {
    var value:String;
    var label:String;
}

/** A text and its translation into the page's language. **/
@:well.view
typedef AdminTranslationItemView = {
    var id:Int;
    var namespace:String;
    var sourceName:String;
    var key:String;
    var origin:String;
    var audience:String;
    var plural:Bool;
    var sourceLanguage:String;
    var source:String;
    var sourceOne:String;
    var sourceOther:String;
    var placeholders:Array<String>;
    var shipped:String;
    var shippedOne:String;
    var shippedOther:String;

    /** The shipped translation as one line, with both plural forms. **/
    var shippedText:String;

    var value:String;
    var valueOne:String;
    var valueOther:String;
    var effective:String;

    /** `source`, `missing`, `translated` (shipped), `edited`, `review` or `unused`. **/
    var status:String;

    var outdated:Bool;
    var sourceEditable:Bool;
}

@:well.view
typedef AdminTranslationEntryView = {
    var language:String;
    var name:String;
    var enabled:Bool;
    var translation:AdminTranslationItemView;
}
