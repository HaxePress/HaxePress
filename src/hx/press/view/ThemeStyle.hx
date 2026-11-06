package hx.press.view;

import haxe.ds.StringMap;
import wellout.render.Values;

/**
    CSS custom properties from theme settings, validated before they reach
    a `style` attribute: colors must be `#rrggbb` and the content width is a
    clamped number of pixels.
**/
class ThemeStyle {
    static final color = ~/^#[0-9a-fA-F]{6}$/;
    static final variableName = ~/^--[a-z][a-z0-9-]*$/;
    static final safeValue = ~/^(?:#[0-9a-fA-F]{6}|-?[0-9]+(?:\.[0-9]+)?(?:px|rem|em|%)?)$/;
    static final colorSettings = [
        ["accent", "--green"],
        ["paper", "--paper"],
        ["ink", "--ink"],
        ["button_color", "--theme-button-background"],
        ["button_text_color", "--theme-button-text"]
    ];

    /** The Simple layout's variables for the theme's settings. **/
    public static function variables(theme:Dynamic):Map<String, String> {
        var result:Map<String, String> = [];
        var settings:Dynamic = theme == null ? null : theme.settings;
        for (pair in colorSettings) {
            var value = settings == null ? null : Values.toText(Values.field(settings, pair[0]));
            if (value != null && color.match(value)) {
                result.set(pair[1], value);
            }
        }
        var configured = settings == null ? null : Values.toText(Values.field(settings, "width"));
        var width = configured == null || configured == "" ? 760.0 : Std.parseFloat(configured);
        if (!Math.isFinite(width)) {
            width = 760;
        }
        width = Math.max(640, Math.min(960, width));
        result.set("--content-width", '${Std.int(width)}px');
        return result;
    }

    static final fontStack = ~/^(?:'[A-Za-z0-9 -]{1,40}'|[A-Za-z-]{1,40})(?:, ?(?:'[A-Za-z0-9 -]{1,40}'|[A-Za-z-]{1,40})){0,5}$/;

    /** A clamped pixel length from a numeric setting, such as a content width. **/
    public static function pixels(value:Null<String>, minimum:Int, maximum:Int,
            fallback:Int):String {
        var number = value == null || value == "" ? Math.NaN : Std.parseFloat(value);
        if (!Math.isFinite(number)) {
            number = fallback;
        }
        number = Math.max(minimum, Math.min(maximum, number));
        return '${Std.int(number)}px';
    }

    /**
        Custom properties from a record such as `{ green: …, contentWidth: … }`:
        names become `--green` and `--content-width`, null values are left
        out, and values must be colors, lengths or a simple font stack.
    **/
    public static function fromRecord(input:Dynamic):String {
        if (input == null) {
            return "";
        }
        var output:Array<String> = [];
        for (field in Reflect.fields(input)) {
            var value = Values.toText(Reflect.field(input, field));
            if (value == null || value == "") {
                continue;
            }
            var name = "--"
                + ~/([a-z0-9])([A-Z])/g.map(field,
                    match -> '${match.matched(1)}-${match.matched(2).toLowerCase()}')
                    .toLowerCase();
            if (variableName.match(name) && (safeValue.match(value) || fontStack.match(value))) {
                output.push('${name}: ${value}');
            }
        }
        return output.join("; ");
    }

    /** `--name: value;` declarations; entries with an unexpected name or value are dropped. **/
    public static function declarations(input:Dynamic):String {
        if (input == null || !Std.isOfType(input, StringMap)) {
            return "";
        }
        var map:StringMap<String> = cast input;
        var keys = [for (key in map.keys()) key];
        keys.sort(Reflect.compare);
        var output:Array<String> = [];
        for (key in keys) {
            var value = map.get(key);
            if (variableName.match(key) && value != null && safeValue.match(value)) {
                output.push('${key}: ${value}');
            }
        }
        return output.join("; ");
    }
}
