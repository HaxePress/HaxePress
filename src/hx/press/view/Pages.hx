package hx.press.view;

import haxe.Exception;
import hx.well.http.Response;

/**
    Renders an application page by name, such as `Admin/PluginPage`, for
    plugins. The JVM host installs its renderer when it boots; this class
    has no dependency on the renderer, so plugin SDKs of every target can
    export it.
**/
class Pages {
    public static var renderer:Null<(name:String, props:Dynamic) -> Response> = null;

    public static function render(name:String, props:Dynamic):Response {
        if (renderer == null) {
            throw new Exception('Pages are rendered by the HaxePress host; ${name} is unavailable here.');
        }
        return renderer(name, props);
    }
}
