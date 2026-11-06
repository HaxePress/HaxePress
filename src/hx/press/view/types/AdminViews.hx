package hx.press.view.types;

import hx.press.view.types.admin.SystemViews.ExtensionSettingFieldView;
import wellout.Url;

@:well.view
typedef AdminSidebarLinkView = {
    var href:Url;
    var label:String;
    var icon:String;
    var current:Bool;
    var child:Bool;
}

@:well.view
typedef AdminSidebarGroupView = {
    var label:String;
    var links:Array<AdminSidebarLinkView>;
}

/** The breadcrumb of an admin page: its group, an optional parent link and the page. */
@:well.view
typedef AdminLocationView = {
    var group:String;
    var current:String;
    @:optional var parentHref:Url;
    @:optional var parentLabel:String;
}

@:well.view
typedef AdminCategoryView = {
    var id:Int;
    var name:String;
    var items:Int;
}

@:well.view
typedef AdminCategoryFormView = {
    var id:String;
    var name:String;
}

/**
    The theme preview page. `saved` holds the stored setting values the
    customizer compares with; `fields` show the values being edited, which
    after a failed save are the submitted ones.
**/
@:well.view
typedef ThemePreviewView = {
    var id:String;
    var name:String;
    var url:Url;
    var customizable:Bool;
    var dirty:Bool;
    var fields:Array<ExtensionSettingFieldView>;
    var saved:Map<String, String>;
}
