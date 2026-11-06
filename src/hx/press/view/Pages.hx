package hx.press.view;

import haxe.Exception;
import hx.well.http.Request;
import hx.well.http.Response;

/**
    Renders pages for plugins: an application page by name, such as
    `Admin/PluginPage`, or one of the plugin's own templates. The JVM host
    installs its renderers when it boots; this class has no dependency on
    the renderer, so plugin SDKs of every target can export it.
**/
class Pages {
    public static var renderer:Null<(name:String, props:Dynamic) -> Response> = null;
    public static var viewRenderer:Null<(name:String, props:Dynamic) -> Response> = null;
    public static var validationRedirector:Null<(request:Request, scope:String, message:String,
            url:String) -> Null<Response>> = null;
    public static var validationRedirects:Null<Request->Bool> = null;

    public static function render(name:String, props:Dynamic):Response {
        if (renderer == null) {
            throw new Exception('Pages are rendered by the HaxePress host; ${name} is unavailable here.');
        }
        return renderer(name, props);
    }

    /**
        Renders the template `name` from the views folder of the plugin whose
        route handles the request, such as `views/Reports.well.html`.
    **/
    public static function view(name:String, props:Dynamic):Response {
        if (viewRenderer == null) {
            throw new Exception('Pages are rendered by the HaxePress host; ${name} is unavailable here.');
        }
        return viewRenderer(name, props);
    }

    /**
        Whether a failed form submission should redirect back to its page
        with flashed errors, as browsers expect, instead of answering JSON.
    **/
    public static function redirectsValidation(request:Request):Bool {
        return validationRedirects != null && validationRedirects(request);
    }

    /**
        For a browser form, keeps `message` as the error of `scope` and the
        submitted values without secrets, and redirects to `url`; null for a
        JSON request, which answers with its own error.
    **/
    public static function validationRedirect(request:Request, scope:String, message:String,
            url:String):Null<Response> {
        return validationRedirector == null ? null : validationRedirector(request, scope, message,
            url);
    }
}
