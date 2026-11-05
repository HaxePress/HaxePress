package hx.press.themes;

import haxe.Exception;
import haxe.Json;
import haxe.io.Bytes;

class ThemeDesignSchema {
    public static inline var MAX_BYTES = 1048576;
    public static inline var MAX_NODES = 2048;
    public static inline var MAX_DEPTH = 16;
    public static final templates = ["Home", "ContentIndex", "ContentDetail", "Page", "About", "NotFound"];
    public static final blockTypes = [
        "container",
        "element",
        "heading",
        "text",
        "image",
        "button",
        "spacer",
        "divider",
        "brand",
        "navigation",
        "repeat",
        "component",
        "extension",
        "pagination",
        "search",
        "content-list",
        "content-title",
        "content-excerpt",
        "content-image",
        "content-body",
        "site-description"
    ];

    public static function parse(source:String):Dynamic {
        if (Bytes.ofString(source).length > MAX_BYTES) {
            throw new Exception("The theme design exceeds the 1 MB document limit.");
        }
        var input:Dynamic;
        try {
            input = Json.parse(source);
        } catch (_:Dynamic) {
            throw new Exception("The theme design must contain valid JSON.");
        }
        var document = new ThemeDesignValidator().validate(input);
        if (Bytes.ofString(Json.stringify(document)).length > MAX_BYTES) {
            throw new Exception("The normalized theme design exceeds the 1 MB document limit.");
        }
        return document;
    }

    public static function starter(blank:Bool):Dynamic {
        return parse(Json.stringify(legacyStarter(blank)));
    }

    static function block(id:String, type:String, text:String = ""):Dynamic {
        return {
            id: id,
            type: type,
            text: text,
            href: "",
            image: "",
            alt: "",
            level: 1
        };
    }

    static function section(id:String, name:String, blocks:Array<Dynamic>,
            padding:Int = 48):Dynamic {
        return {
            id: id,
            name: name,
            background: "",
            color: "",
            padding: padding,
            columns: 1,
            align: "left",
            width: "content",
            blocks: blocks
        };
    }

    static function legacyStarter(blank:Bool):Dynamic {
        var pages:Dynamic = {};
        for (name in templates) {
            var types = switch (name) {
                case "Home", "ContentIndex": ["heading", "content-list"];
                case "ContentDetail",
                    "Page": ["content-title", "content-excerpt", "content-image", "content-body"];
                case "About": ["heading", "site-description"];
                default: ["heading", "text"];
            };
            var title = switch (name) {
                case "Home": "Latest content";
                case "ContentIndex": "Content";
                case "About": "About";
                case "NotFound": "Page not found";
                default: "";
            };
            var blocks = [
                for (index in 0...types.length)
                    block(name + "-block-" + index, types[index],
                        index == 0 ? title : name == "NotFound" ? "This page could not be found." : "")
            ];
            Reflect.setField(pages, name, blank && name == "Home" ? [] : [section(name
                + "-section", title == "" ? "Content" : title, blocks)]);
        }
        var header = section("header", "Header",
            [block("brand", "brand"), block("header-nav", "navigation")], 24);
        header.columns = 2;
        return {
            schema: 1,
            tokens: {
                background: "#ffffff",
                text: "#1d2939",
                accent: "#3456c4",
                font: "sans",
                width: 1120,
                radius: 8
            },
            header: [header],
            footer: [section("footer", "Footer", [block("footer-nav", "navigation")], 32)],
            templates: pages
        };
    }
}
