package hx.press.content;

typedef ContentFieldDefinition = {
    var key:String;
    var label:String;
    var kind:String;
    var required:Bool;
    var publicVisible:Bool;
    var filterable:Bool;
    var inList:Bool;
    var help:String;
    var options:Array<{value:String, label:String}>;
}

typedef ContentTypeDefinition = {
    var key:String;
    var name:String;
    var singular:String;
    var description:String;
    var icon:String;
    var adminBase:String;
    var publicBase:String;
    var publicVisible:Bool;
    var hasArchive:Bool;
    var enabled:Bool;
    var system:Bool;
    var owner:String;
    var capability:String;
    var position:Int;
    var template:String;
    var archiveTemplate:String;
    var features:Array<String>;
    var fields:Array<ContentFieldDefinition>;
    var labels:Dynamic;
    var minimumTitleLength:Int;
    var minimumContentLength:Int;
    var minimumExcerptLength:Int;
}

typedef ContentTypeRecord = {
    var key:String;
    var name:String;
    var singular:String;
    var description:String;
    var icon:String;
    var admin_path:String;
    var public_path:String;
    var public_visible:Int;
    var has_archive:Int;
    var enabled:Int;
    var system:Int;
    var owner:String;
    var capability:String;
    var position:Int;
    var template:String;
    var archive_template:String;
    var features:String;
    var fields:String;
    var labels:String;
    var minimum_title_length:Int;
    var minimum_content_length:Int;
    var minimum_excerpt_length:Int;
}

typedef ContentTypeSummary = {
    var key:String;
    var name:String;
    var singular:String;
    var icon:String;
    var admin_path:String;
    var public_path:String;
    var public_visible:Int;
    var enabled:Int;
    var system:Int;
    var owner:String;
    var capability:String;
    var position:Int;
    @:optional var items:Int;
    @:optional var owner_active:Int;
}
