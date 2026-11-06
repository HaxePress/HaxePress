package hx.press.view;

import wellout.render.Values;
import haxe.ds.StringMap;
import haxe.Json;
import hx.press.ai.AdminMcpAccess;
import hx.press.i18n.I18n;
import hx.press.install.InstallationState;
import hx.press.media.MediaReferences;
import hx.press.plugins.PluginHealth;
import hx.press.themes.ThemeFeedData;
import hx.well.facades.Environment;
import hx.well.http.Request;
import hx.well.http.RequestStatic;
import hx.well.http.Response;
import hx.well.http.StringResponse;
import hx.well.internal.SecureToken;
import wellout.ByteWriter;
import wellout.render.Renderer;
import wellout.syntax.Diagnostic;

/**
    Renders HaxePress pages with Wellout. `View.render(name, props)` takes
    the page name the controllers used before (`Home`, `Admin/Tags`) and
    the same props. The browser receives HTML; page data stays on the
    server.
**/
class View {
    static inline final SHARED = "hx.press.view.shared";
    static inline final NONCE = "hx.press.view.nonce";
    public static inline final FRAGMENT_HEADER = "Well-Fragment";

    /** Lets test runs inspect any page as data with `X-Well-Data: true` (see `isDataRequest`). **/
    static final dataResponses:Bool = Environment.env("WELL_DATA_RESPONSES", "") == "1";

    public static function render(name:String, ?props:Dynamic):Response {
        var request = RequestStatic.request();
        Flash.consume(request);
        if (isDataRequest(request)) {
            return data(name, props, request);
        }
        var target = ViewEngine.target(name, request);
        var compiled = target.set.template(target.template);
        if (compiled.value == null) {
            return failure(target.template, compiled.diagnostics, target.set);
        }
        var fragment = requestedFragment(request);
        var writer = ViewResponse.acquire();
        writer.reset();
        var host = new ViewHost(request, props, target.namespace, target.assetBase, target.mapper);
        var maxOutput = target.untrusted ? 2097152 : 0;
        var maxDepth = target.untrusted ? 16 : 32;
        try {
            var found = Renderer.render(compiled.value, props, host, writer, {
                fragment: fragment,
                maxOutput: maxOutput,
                maxComponentDepth: maxDepth
            });
            if (!found) {
                fragment = null;
                writer.reset();
                Renderer.render(compiled.value, props, host, writer, {
                    maxOutput: maxOutput,
                    maxComponentDepth: maxDepth
                });
            }
        } catch (error:Dynamic) {
            ViewResponse.discard(writer);
            trace('Rendering ${target.template} failed: ${error}');
            return
                new StringResponse('<!doctype html><title>Error</title><p>The page could not be rendered.</p>',
                    500);
        }
        var response = new ViewResponse(writer, 200);
        response.header("Vary", FRAGMENT_HEADER);
        if (ViewRoots.isAdmin(request)) {
            // Administration pages are not kept for the back button after signing out.
            response.header("Cache-Control", "private, no-store");
        }
        if (fragment != null) {
            response.header(FRAGMENT_HEADER, fragment);
        }
        return response;
    }

    static function requestedFragment(request:Null<Request>):Null<String> {
        if (request == null) {
            return null;
        }
        var header = request.header(FRAGMENT_HEADER);
        if (header != null && header != "") {
            return header;
        }
        var query = request.query("_fragment", "");
        return query == "" ? null : query;
    }

    static function failure(name:String, diagnostics:Array<Diagnostic>, set:Dynamic):Response {
        var lines = [];
        for (diagnostic in diagnostics) {
            if (diagnostic.isError()) {
                lines.push('${name}:${diagnostic.position}: ${diagnostic.message} [${diagnostic.code}]');
            }
        }
        trace('Template ${name} has errors:\n${lines.join("\n")}');
        var details = StringTools.htmlEscape(lines.join("\n"));
        return
            new StringResponse('<!doctype html><title>Template error</title><h1>Template error</h1><pre>${details}</pre>',
            500);
    }

    /** Shares a root value, such as a preview theme, for the rest of this request. **/
    public static function share(key:String, value:Dynamic):Void {
        var request = RequestStatic.request();
        if (request == null) {
            return;
        }
        var values = shared(request);
        if (values == null) {
            values = [];
            request.setAttribute(SHARED, values);
        }
        values.set(key, value);
    }

    public static function shareAll(values:Map<String, Dynamic>):Void {
        for (key => value in values) {
            share(key, value);
        }
    }

    public static function shared(request:Null<Request>):Null<Map<String, Dynamic>> {
        return request == null ? null : request.getAttribute(SHARED, null);
    }

    public static function sharedValue(request:Null<Request>, key:String):Dynamic {
        var values = shared(request);
        return values == null ? null : values.get(key);
    }

    /** Keeps a value in the session for the next rendered page, such as validation errors. **/
    public static function flash(key:String, value:Dynamic):Void {
        Flash.put(key, value);
    }

    public static function flashed(request:Null<Request>, key:String):Dynamic {
        return Flash.get(request, key);
    }

    /** Validation errors: flashed by a redirect, then those the page props carry. **/
    public static function errors(request:Null<Request>, props:Dynamic):Map<String, String> {
        var errors:Map<String, String> = [];
        var stored:Dynamic = flashed(request, "errors");
        copyErrors(stored, errors);
        if (props != null) {
            copyErrors(Values.field(props, "errors"), errors);
        }
        return errors;
    }

    static function copyErrors(source:Dynamic, target:Map<String, String>):Void {
        if (source == null) {
            return;
        }
        if (Std.isOfType(source, StringMap)) {
            var map:Map<String, Dynamic> = cast source;
            for (key => value in map) {
                target.set(key, errorText(value));
            }
            return;
        }
        for (field in Reflect.fields(source)) {
            target.set(field, errorText(Reflect.field(source, field)));
        }
    }

    /** The first message of a nested error value, like the former `errorText`. **/
    public static function errorText(value:Dynamic):String {
        if (value == null) {
            return "";
        }
        if (Std.isOfType(value, String)) {
            return value;
        }
        if (Std.isOfType(value, Array)) {
            var items:Array<Dynamic> = cast value;
            for (item in items) {
                var text = errorText(item);
                if (text != "") {
                    return text;
                }
            }
            return "";
        }
        if (Std.isOfType(value, StringMap)) {
            var map:Map<String, Dynamic> = cast value;
            for (item in map) {
                var text = errorText(item);
                if (text != "") {
                    return text;
                }
            }
            return "";
        }
        for (field in Reflect.fields(value)) {
            var text = errorText(Reflect.field(value, field));
            if (text != "") {
                return text;
            }
        }
        return "";
    }

    public static function old(request:Null<Request>, field:String):Null<String> {
        var values:Dynamic = flashed(request, "old");
        if (values == null) {
            return null;
        }
        var value = Values.field(values, field);
        return value == null ? null : Std.string(value);
    }

    public static function notice(request:Null<Request>):String {
        var value:Dynamic = flashed(request, "notice");
        return value == null ? "" : Std.string(value);
    }

    public static function nonce(request:Request):String {
        var value:Null<String> = request.getAttribute(NONCE, null);
        if (value == null) {
            value = SecureToken.generate(22);
            request.setAttribute(NONCE, value);
        }
        return value;
    }

    /**
        Whether to answer with page data instead of HTML: for tests, with the
        `WELL_DATA_RESPONSES` switch, and for the site MCP host, which reads
        administration pages as data on its authenticated internal requests.
    **/
    public static function isDataRequest(request:Null<Request>):Bool {
        if (request == null || request.header("X-Well-Data") != "true") {
            return false;
        }
        return dataResponses || request.getAttribute(AdminMcpAccess.INTERNAL, false) == true;
    }

    /**
        Whether a failed form submission should redirect back with flashed
        errors (post/redirect/get), as browsers and page-data tests expect.
    **/
    public static function redirectsValidation(request:Null<Request>):Bool {
        if (request == null) {
            return false;
        }
        if (isDataRequest(request)) {
            return true;
        }
        var accept = request.header("Accept");
        return accept != null && accept.indexOf("text/html") >= 0;
    }

    /** Page data as JSON for tests: `{component, props, url}` with the shared values. **/
    static function data(name:String, props:Dynamic, request:Request):Response {
        var merged:Dynamic = {};
        ViewData.assign(merged, sharedProps(request, props));
        ViewData.assign(merged, props);
        var errors = errors(request, props);
        Reflect.setField(merged, "errors", ViewData.plain(errors));
        var host = new ViewHost(request, props, "cms");
        var requestView:Dynamic = host.root("request");
        var payload = {
            component: name,
            props: merged,
            url: requestView.url,
            version: ""
        };
        var response = new StringResponse(Json.stringify(payload), 200);
        response.header("Content-Type", "application/json");
        response.header("Vary", "X-Well-Data");
        response.header("X-Well-Data", "true");
        return response;
    }

    /** The values pages used to receive as shared props, for page-data responses. **/
    static function sharedProps(request:Request, props:Dynamic):Map<String, Dynamic> {
        if (InstallationState.pending) {
            // The installer has no database yet; its shared values were fixed, as with Inertia.
            return [
                "site" => {site_name: "HaxePress"},
                "theme" => null,
                "auth" => null,
                "csrfToken" => null
            ];
        }
        var host = new ViewHost(request, props, "cms");
        var values:Map<String, Dynamic> = [
            "site" => host.root("site"),
            "i18n" => I18n.props(),
            "categories" => [],
            "primaryArchive" => host.root("primaryArchive"),
            "siteUrl" => host.root("siteUrl"),
            "mediaRules" => MediaReferences.rules()
        ];
        if (ViewRoots.isAdmin(request)) {
            values.set("auth", host.root("auth"));
            values.set("csrfToken", host.csrfToken());
            values.set("pluginRestartRequired", PluginHealth.restartRequired);
            values.set("adminNavigation", host.root("adminNavigation"));
            values.set("pluginNavigation", host.root("pluginNavigation"));
        } else {
            var theme:Dynamic = host.root("theme");
            values.set("auth", null);
            values.set("csrfToken", null);
            values.set("theme", theme);
            values.set("navigation", host.root("navigation"));
            values.set("pluginNavigation", host.root("pluginNavigation"));
            values.set("extensions", host.root("extensions"));
            var selected:String = theme != null
                && theme.studioScope != null ? theme.studioScope : request.getAttribute("hx.press.theme.template",
                    "Home");
            values.set("themeFeeds",
                ThemeFeedData.resolve(theme, selected,
                    request.getAttribute("hx.press.theme.fallback", "Home")));
        }
        var shared = shared(request);
        if (shared != null) {
            for (key => value in shared) {
                values.set(key, value);
            }
        }
        return values;
    }
}
