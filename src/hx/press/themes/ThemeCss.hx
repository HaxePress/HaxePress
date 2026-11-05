package hx.press.themes;

import haxe.Exception;
import hx.press.media.MediaReferences;

/** Keep stylesheet resources on configured media or application asset routes. */
class ThemeCss {
    static function decoded(source:String):String {
        var output = new StringBuf();
        var index = 0;
        while (index < source.length) {
            var character = source.charAt(index++);
            if (character != "\\" || index >= source.length) {
                output.add(character);
                continue;
            }
            var hex = "";
            while (index < source.length && hex.length < 6
                && ~/^[0-9a-fA-F]$/.match(source.charAt(index))) {
                hex += source.charAt(index++);
            }
            if (hex != "") {
                var code = Std.parseInt("0x" + hex);
                output.add(String.fromCharCode(code));
                if (index < source.length && ~/\s/.match(source.charAt(index))) {
                    index++;
                }
            } else {
                output.add(source.charAt(index++));
            }
        }
        return output.toString();
    }

    static function resource(value:String):String {
        var url = StringTools.trim(value);
        if ((StringTools.startsWith(url, "\"") && StringTools.endsWith(url, "\""))
            || (StringTools.startsWith(url, "'") && StringTools.endsWith(url, "'"))) {
            url = url.substr(1, url.length - 2);
        }
        var applicationAsset = ~/^\/(build\/assets|fonts|images)\/[A-Za-z0-9_.\/-]+$/.match(url);
        var localFragment = ~/^#[A-Za-z][A-Za-z0-9_-]{0,79}$/.match(url);
        if ((MediaReferences.imageUrl(url)
            || ThemeAssets.imageUrl(url)
            || localFragment
            || applicationAsset)
            && url.indexOf("..") < 0) {
            return url;
        }
        throw new Exception("CSS resources must use the media library or application assets.");
    }

    static function quoted(value:String, quote:String):String {
        var escaped = StringTools.replace(value, "\\", "\\\\");
        escaped = StringTools.replace(escaped, quote, "\\" + quote);
        escaped = StringTools.replace(escaped, "\n", "\\a ");
        escaped = StringTools.replace(escaped, "\r", "\\d ");
        return quote + escaped + quote;
    }

    /** Canonical URL/string escapes keep persisted CSS references visible to the media API. */
    static function canonical(source:String):String {
        var output = new StringBuf();
        var index = 0;
        while (index < source.length) {
            var character = source.charAt(index);
            if (character == "/" && source.charAt(index + 1) == "*") {
                var end = source.indexOf("*/", index + 2);
                if (end < 0) {
                    throw new Exception("Close every CSS comment.");
                }
                output.add(" ");
                index = end + 2;
            } else if (character == "\"" || character == "'") {
                var quote = character;
                var start = ++index;
                while (index < source.length) {
                    if (source.charAt(index) == "\\") {
                        index += 2;
                    } else if (source.charAt(index) == quote) {
                        break;
                    } else {
                        index++;
                    }
                }
                if (index >= source.length) {
                    throw new Exception("Close every CSS string.");
                }
                output.add(quoted(decoded(source.substring(start, index)), quote));
                index++;
            } else if (~/[a-zA-Z_-]/.match(character) || character == "\\") {
                var start = index;
                while (index < source.length) {
                    var current = source.charAt(index);
                    if (current == "\\") {
                        index++;
                        var hex = 0;
                        while (index < source.length && hex < 6
                            && ~/^[0-9a-fA-F]$/.match(source.charAt(index))) {
                            index++;
                            hex++;
                        }
                        if (hex == 0 && index < source.length) {
                            index++;
                        } else if (index < source.length && ~/\s/.match(source.charAt(index))) {
                            index++;
                        }
                    } else if (~/^[a-zA-Z0-9_-]$/.match(current)) {
                        index++;
                    } else {
                        break;
                    }
                }
                var word = source.substring(start, index);
                if (decoded(word).toLowerCase() == "url" && source.charAt(index) == "(") {
                    var startUrl = ++index;
                    var quote = "";
                    while (index < source.length) {
                        var current = source.charAt(index);
                        if (current == "\\") {
                            index += 2;
                            continue;
                        }
                        if (quote != "") {
                            if (current == quote) {
                                quote = "";
                            }
                        } else if (current == "\"" || current == "'") {
                            quote = current;
                        } else if (current == ")") {
                            break;
                        }
                        index++;
                    }
                    var url = resource(decoded(source.substring(startUrl, index)));
                    output.add("url(" + quoted(url, "\"") + ")");
                    index++;
                } else {
                    output.add(word);
                }
            } else {
                output.add(character);
                index++;
            }
        }
        return output.toString();
    }

    public static function validate(source:String, stylesheet:Bool = false):String {
        source = canonical(source);
        var normalized = decoded(source);
        if (~/@import\b|<\s*\/\s*style\b|expression\s*\(|-moz-binding|behavior\s*:/i.match(normalized)) {
            throw new Exception("Use theme CSS without imports, executable values or HTML markup.");
        }
        var urls = ~/url\(\s*([^)]*)\)/ig;
        var offset = 0;
        while (urls.matchSub(normalized, offset)) {
            resource(urls.matched(1));
            var position = urls.matchedPos();
            offset = position.pos + position.len;
        }
        var withoutUrls = ~/url\(\s*([^)]*)\)/ig.replace(normalized, "");
        var remote = ~/(?:https?:|data:|blob:|file:|javascript:|\/\/)/i;
        if (remote.match(withoutUrls)) {
            throw new Exception("Use local uploaded images and application assets in CSS.");
        }
        if (!stylesheet) {
            return canonical(source);
        }
        var quote = "";
        var braces = 0;
        var comment = false;
        var index = 0;
        while (index < source.length) {
            var character = source.charAt(index);
            var next = source.charAt(index + 1);
            if (comment) {
                if (character == "*" && next == "/") {
                    comment = false;
                    index++;
                }
            } else if (character == "\\") {
                index++;
            } else if (quote != "") {
                if (character == quote) {
                    quote = "";
                }
            } else if (character == "/" && next == "*") {
                comment = true;
                index++;
            } else if (character == "\"" || character == "'") {
                quote = character;
            } else if (character == "{") {
                braces++;
            } else if (character == "}") {
                braces--;
                if (braces < 0) {
                    throw new Exception("Close CSS rules inside the theme stylesheet.");
                }
            }
            index++;
        }
        if (braces != 0 || quote != "" || comment) {
            throw new Exception("Close every CSS rule, string and comment.");
        }
        return canonical(source);
    }
}
