package hx.press.view.types;

import wellout.Url;

@:well.view
typedef FieldOptionView = {
    var label:String;
    var value:String;
}

@:well.view
typedef FieldDefinitionView = {
    var key:String;
    var label:String;
    var kind:String;
    var help:String;
    var required:Bool;
    var publicVisible:Bool;
    var filterable:Bool;
    var inList:Bool;
    var options:Array<FieldOptionView>;
}

/** A public field value prepared for display (see `FieldDisplay`). */
@:well.view
typedef FieldValueView = {
    var key:String;
    var label:String;
    var kind:String;
    var text:String;
    var image:String;
}

@:well.view
typedef TagView = {
    var id:Int;
    var name:String;
    var slug:String;
    var description:String;
    @:optional var url:Url;
    @:optional var items:Int;
}

@:well.view
typedef ContentItemView = {
    var id:Int;
    var title:String;
    var slug:String;
    var excerpt:String;
    var category:String;

    /** The category name in the page\'s language; `category` stays the name filters use. **/
    var categoryLabel:String;

    var image:Url;
    var image_alt:String;
    var status:String;
    var featured:Bool;
    var published_at:String;
    var publishedLabel:String;
    var updated_at:String;
    var updatedLabel:String;
    var readMinutes:Int;
    var content_type:String;
    var url:Url;
    var archiveUrl:Url;
    var typeLabel:String;
    var showReadingTime:Bool;
    @:optional var adminBase:String;
    @:optional var content:String;
    @:optional var tags:Array<TagView>;
    @:optional var seo_title:String;
    @:optional var seo_description:String;
    @:optional var fields:Map<String, Dynamic>;
    @:optional var fieldDefinitions:Array<FieldDefinitionView>;
    @:optional var fieldValues:Array<FieldValueView>;
    @:optional var version:Int;
    @:optional var author_id:Int;
}

@:well.view
typedef PublicCollectionView = {
    var key:String;
    var name:String;
    var singular:String;
    var description:String;
    var publicBase:Url;
    var hasArchive:Bool;
    var features:Array<String>;
    var fields:Array<FieldDefinitionView>;
}

@:well.view
typedef PageLinksView = {
    var previous:Null<Url>;
    var next:Null<Url>;
    var total:Int;
}
