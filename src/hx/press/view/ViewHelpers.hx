package hx.press.view;

import haxe.ds.StringMap;
import haxe.io.Bytes;
import haxe.Json;
import hx.press.CmsAccess;
import hx.press.i18n.I18n;
import hx.press.content.Markdown;
import wellout.ByteWriter;
import wellout.render.Arguments;
import wellout.render.RenderContext;
import wellout.render.Runtime;
import wellout.render.Values;

/** Implementations of the helpers and filters in `ViewContract`. */
class ViewHelpers {
    public static function runtime():Runtime {
        var runtime = new Runtime();
        runtime.addHelper("t", (arguments, context) -> translate(arguments, context),
            (arguments, context, writer) -> writer.text(translate(arguments, context)));
        runtime.addHelper("can", (arguments, _) -> CmsAccess.can(arguments.string(0)));
        runtime.addHelper("icon", (arguments, _) -> Icons.svg(arguments.string(0)),
            (arguments, _, writer) -> Icons.write(arguments.string(0), writer));
        runtime.addHelper("markdown", (arguments, _) -> Markdown.render(arguments.string(0)),
            (arguments, _, writer) -> writer.trusted(Markdown.render(arguments.string(0))));
        runtime.addHelper("asset",
            (arguments, _) -> ViewAssets.url('resources/${arguments.string(0)}'));
        runtime.addHelper("url", (arguments, _) -> url(arguments));
        runtime.addHelper("query", (arguments, context) -> {
            var request = host(context).request;
            return request == null ? "" : request.query(arguments.string(0), "");
        });
        runtime.addHelper("old",
            (arguments, context) -> View.old(host(context).request, arguments.string(0)));
        runtime.addHelper("error", (arguments, context) -> {
            var errors:Map<String, String> = host(context).root("errors");
            return errors == null ? null : errors.get(arguments.string(0));
        });
        runtime.addHelper("year", (_, _) -> Date.now().getUTCFullYear());
        runtime.addHelper("initials", (arguments, _) -> AdminChrome.initials(arguments.string(0)));
        runtime.addHelper("join", (arguments, _) -> {
            var items:Array<Dynamic> = arguments.get(0);
            var separator = arguments.string(1, ", ");
            return items == null ? "" : [for (item in items) Values.toText(item)].join(separator);
        });
        runtime.addHelper("active", (arguments, context) -> active(arguments, context));
        runtime.addHelper("fieldValues",
            (arguments, _) -> FieldDisplay.values(arguments.get(0), arguments.get(1)));
        runtime.addHelper("themeVariables",
            (_, context) -> ThemeStyle.variables(host(context).root("theme")));
        runtime.addHelper("defaultNavigation", (_, _) -> defaultNavigation);
        runtime.addHelper("isCurrent",
            (arguments, context) -> publicPath(context) == arguments.string(0));
        runtime.addHelper("returnPath", (_, context) -> returnPath(context));
        runtime.addHelper("size", (arguments, _) -> {
            var items:Null<Array<Dynamic>> = arguments.get(0);
            return items == null ? 0 : items.length;
        });
        runtime.addHelper("any", (arguments, _) -> anyValue(arguments.get(0)));
        runtime.addFilter("string", (input, _, _) -> Values.toText(input));
        runtime.addFilter("encode", (input, _, _) -> encodeComponent(Values.toText(input)));
        runtime.addFilter("replace",
            (input, arguments,
                    _) -> StringTools.replace(Values.toText(input), arguments.string(0),
                    arguments.string(1)));
        runtime.addHelper("themeAsset", (arguments, context) -> {
            var theme:Dynamic = host(context).root("theme");
            var base:String = theme == null || theme.assetBase == null ? "" : theme.assetBase;
            var path = arguments.string(0);
            return ~/^[A-Za-z0-9_\/-]+(?:\.[A-Za-z0-9_-]+)+(?![\s\S])/.match(path)
                && path.indexOf("..") < 0 ? '${base}${path}' : "";
        });
        // A file of the plugin or theme package whose template is rendering.
        runtime.addHelper("packageAsset", (arguments, context) -> {
            var base = host(context).packageAssetBase;
            var path = arguments.string(0);
            return base != null
                && ~/^[A-Za-z0-9_\/-]+(?:\.[A-Za-z0-9_-]+)+(?![\s\S])/.match(path)
                && path.indexOf("..") < 0 ? '${base}${path}' : "";
        });
        runtime.addFilter("slice", (input, arguments, _) -> {
            var text = Values.toText(input);
            var end:Null<Int> = arguments.get(1);
            return
                end == null ? text.substring(arguments.int(0)) : text.substring(arguments.int(0),
                    end);
        });
        runtime.addFilter("pixels",
            (input, arguments,
                    _) -> ThemeStyle.pixels(Values.toText(input), arguments.int(0),
                    arguments.int(1),
                    arguments.int(2)));
        runtime.addHelper("designLink", (arguments, _) -> DesignViews.link(arguments.get(0)));
        runtime.addHelper("designImage", (arguments, _) -> DesignViews.image(arguments.get(0)));
        runtime.addHelper("designStylesheet", (_, context) -> {
            var theme:Dynamic = host(context).root("theme");
            return theme == null
                || theme.design == null ? "" : DesignViews.compiled(Std.string(theme.id),
                    theme.design)
                    .stylesheet;
        });
        runtime.addHelper("withFeatured", (arguments, _) -> {
            var featured:Dynamic = arguments.get(0);
            var items:Array<Dynamic> = arguments.get(1);
            return featured == null ? items : [featured].concat(items == null ? [] : items);
        });
        runtime.addHelper("canvasName", (_, context) -> {
            var request = host(context).request;
            return request == null ? "Home" : request.getAttribute(ThemeViews.CANVAS_TEMPLATE,
                "Home");
        });
        runtime.addHelper("pageProps", (_, context) -> ViewData.plain(host(context).props));
        runtime.addHelper("canvasShared", (_, context) -> DesignCanvas.shared(host(context)));
        runtime.addFilter("cssVariables", (input, _, _) -> ThemeStyle.fromRecord(input),
            (input, _, _, writer) -> writer.text(ThemeStyle.fromRecord(input)));
        runtime.addFilter("variables", (input, _, _) -> ThemeStyle.declarations(input),
            (input, _, _, writer) -> writer.text(ThemeStyle.declarations(input)));
        runtime.addFilter("json", (input, _, _) -> Json.stringify(ViewData.plain(input)));
        runtime.addHelper("translate", (arguments, context) -> translateIn(arguments, context));
        return runtime;
    }

    /** `translate(namespace, key, name: value, …)`: the namespace's message, else the CMS one. **/
    static function translateIn(arguments:Arguments, context:RenderContext):String {
        var namespace = arguments.string(0);
        var parameters:Null<Map<String, Dynamic>> = null;
        if (arguments.extraCount > 0) {
            parameters = [];
            for (index in 0...arguments.extraCount) {
                parameters.set(arguments.extraName(index), arguments.extraValue(index));
            }
        }
        var key = arguments.string(1);
        var selected = namespace == "" ? "cms" : namespace;
        // Administration pages also name inactive packages, in their own catalogues.
        return ViewRoots.isAdmin(host(context).request) ? I18n.installedT(key, parameters,
            selected) : I18n.t(key, parameters, selected);
    }

    static final defaultNavigation:Array<Dynamic> = [
        {
            id: 1,
            label: "Home",
            url: "/",
            new_tab: 0
        },
        {
            id: 2,
            label: "Content",
            url: "/content",
            new_tab: 0
        },
        {
            id: 3,
            label: "About",
            url: "/about",
            new_tab: 0
        }
    ];

    /** Whether a list or record holds any truthy value. **/
    static function anyValue(values:Dynamic):Bool {
        if (values == null) {
            return false;
        }
        if (Std.isOfType(values, Array)) {
            var items:Array<Dynamic> = cast values;
            for (item in items) {
                if (Values.truthyDynamic(item)) {
                    return true;
                }
            }
            return false;
        }
        if (Std.isOfType(values, StringMap)) {
            var map:StringMap<Dynamic> = cast values;
            for (item in map) {
                if (Values.truthyDynamic(item)) {
                    return true;
                }
            }
            return false;
        }
        for (field in Reflect.fields(values)) {
            if (Values.truthyDynamic(Reflect.field(values, field))) {
                return true;
            }
        }
        return false;
    }

    /** The page path without a theme preview base, for marking the current link. **/
    static function publicPath(context:RenderContext):String {
        var request = host(context).request;
        if (request == null) {
            return "/";
        }
        var path = request.path;
        var theme:Dynamic = host(context).root("theme");
        var base:Null<String> = theme == null ? null : theme.previewBase;
        if (base != null && base != "" && StringTools.startsWith(path, base)) {
            var rest = path.substr(base.length);
            return rest == "" ? "/" : rest;
        }
        return path;
    }

    /** The current path and query without `lang`, for the language switcher. **/
    static function returnPath(context:RenderContext):String {
        var request = host(context).request;
        if (request == null) {
            return "/";
        }
        var pairs:Array<String> = [];
        for (key => value in request.queries) {
            if (key != "lang") {
                pairs.push('${encodeComponent(key)}=${encodeComponent(value)}');
            }
        }
        return pairs.length == 0 ? request.path : '${request.path}?${pairs.join("&")}';
    }

    /** Percent-encodes like `encodeURIComponent`. **/
    public static function encodeComponent(value:Null<String>):String {
        if (value == null) {
            return "";
        }
        var bytes = Bytes.ofString(value);
        var output = new StringBuf();
        for (index in 0...bytes.length) {
            var code = bytes.get(index);
            var plain = (code >= "A".code && code <= "Z".code)
                || (code >= "a".code && code <= "z".code)
                || (code >= "0".code && code <= "9".code)
                || "-_.!~*'()".indexOf(String.fromCharCode(code)) >= 0;
            if (plain) {
                output.addChar(code);
            } else {
                output.add('%${StringTools.hex(code, 2)}');
            }
        }
        return output.toString();
    }

    static inline function host(context:RenderContext):ViewHost {
        return cast context.host;
    }

    static function translate(arguments:Arguments, context:RenderContext):String {
        var key = arguments.string(0);
        var parameters:Null<Map<String, Dynamic>> = null;
        if (arguments.extraCount > 0) {
            parameters = [];
            for (index in 0...arguments.extraCount) {
                parameters.set(arguments.extraName(index), arguments.extraValue(index));
            }
        }
        return host(context).t(key, parameters);
    }

    /** `url(path, name: value, …)`: the path with non-empty values as its query. **/
    static function url(arguments:Arguments):String {
        var path = arguments.string(0);
        var pairs:Array<String> = [];
        for (index in 0...arguments.extraCount) {
            var value = Values.toText(arguments.extraValue(index));
            if (value != null && value != "") {
                var name = encodeComponent(arguments.extraName(index));
                pairs.push('${name}=${encodeComponent(value)}');
            }
        }
        if (pairs.length == 0) {
            return path;
        }
        var separator = path.indexOf("?") >= 0 ? "&" : "?";
        return '${path}${separator}${pairs.join("&")}';
    }

    /** Whether a navigation link points at the current page. **/
    static function active(arguments:Arguments, context:RenderContext):Bool {
        var request = host(context).request;
        if (request == null) {
            return false;
        }
        var href = arguments.string(0);
        var exact = arguments.get(1) == true;
        var path = request.path;
        var paths:Null<Array<String>> = arguments.get(2);
        var candidates = paths == null ? [href] : [href].concat(paths);
        for (candidate in candidates) {
            if (path == candidate) {
                return true;
            }
            if (!exact && StringTools.startsWith(path, '${candidate}/')) {
                return true;
            }
        }
        return false;
    }
}
