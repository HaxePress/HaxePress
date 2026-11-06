package hx.press.view;

import haxe.Resource;

/**
    The application's Wellout templates, embedded at compile time from
    `resources/views`. Files under `components/` and `layouts/` are
    components named after their file; every other file is a page named
    by its path, such as `Admin/Categories` for
    `pages/Admin/Categories.well.html`.
**/
class ViewSources {
    static final entries:Array<String> = ViewEmbed.templates();

    public static function names():Array<String> {
        return entries.copy();
    }

    public static function source(name:String):Null<String> {
        return Resource.getString('well:${name}');
    }
}
