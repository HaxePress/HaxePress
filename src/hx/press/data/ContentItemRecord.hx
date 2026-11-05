package hx.press.data;

typedef ContentItemRecord = {
    > ContentSummaryRecord,
    var content:String;
    @:optional var version:Int;
    @:optional var author_id:Int;
    @:optional var seo_title:String;
    @:optional var seo_description:String;
    @:optional var scheduled_epoch:Float;
    @:optional var previous_status:String;
}
