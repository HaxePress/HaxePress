package hx.press.data;

import hx.press.database.DatabaseDate;

typedef ContentSummaryRecord = {
    var id:Int;
    var content_type:String;
    var title:String;
    var slug:String;
    var excerpt:String;
    var category:String;
    var image:String;
    var image_alt:String;
    var status:String;
    var featured:Int;
    var reading_minutes:Int;
    var published_at:Null<DatabaseDate>;
    var updated_at:DatabaseDate;
}
