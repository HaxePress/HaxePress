package hx.press.themes;

import haxe.Exception;
import hx.press.media.MediaReferences;

/** Validate one owned document, with per-request state and bounded recursion. */
class ThemeDesignValidator {
    final identifiers:Map<String, Bool> = [];
    var nodes:Int = 0;
    final references:Array<String> = [];
    final sourceReferences:Array<String> = [];

    static final tags = [
        "div",
        "section",
        "article",
        "aside",
        "header",
        "footer",
        "nav",
        "main",
        "figure",
        "figcaption",
        "h1",
        "h2",
        "h3",
        "h4",
        "h5",
        "h6",
        "p",
        "span",
        "a",
        "strong",
        "em",
        "small",
        "blockquote",
        "ul",
        "ol",
        "li",
        "dl",
        "dt",
        "dd",
        "details",
        "summary",
        "time",
        "label",
        "form",
        "input",
        "textarea",
        "select",
        "option",
        "button",
        "table",
        "thead",
        "tbody",
        "tr",
        "th",
        "td",
        "br",
        "hr",
        "pre",
        "code",
        "svg",
        "path",
        "g",
        "defs",
        "circle",
        "ellipse",
        "rect",
        "line",
        "polyline",
        "polygon",
        "linearGradient",
        "radialGradient",
        "stop",
        "clipPath",
        "mask",
        "use",
        "title",
        "desc",
        "text"
    ];
    static final attributes = [
        "id",
        "title",
        "role",
        "name",
        "type",
        "value",
        "placeholder",
        "required",
        "checked",
        "disabled",
        "for",
        "htmlFor",
        "method",
        "action",
        "target",
        "rel",
        "datetime",
        "dateTime",
        "colspan",
        "rowspan",
        "open",
        "min",
        "max",
        "step",
        "pattern",
        "autocomplete",
        "inputmode",
        "maxlength",
        "viewBox",
        "d",
        "fill",
        "stroke",
        "stroke-width",
        "strokeWidth",
        "cx",
        "cy",
        "r",
        "rx",
        "ry",
        "x",
        "y",
        "x1",
        "x2",
        "y1",
        "y2",
        "width",
        "height",
        "points",
        "transform",
        "offset",
        "stop-color",
        "stopColor",
        "clip-path",
        "clipPath",
        "xmlns"
    ];

    public function new() {}

    static function object(value:Dynamic, label:String):Dynamic {
        if (value == null
            || !Reflect.isObject(value)
            || Std.isOfType(value, Array)
            || Std.isOfType(value, String)) {
            throw new Exception(label + " must be an object.");
        }
        return value;
    }

    static function text(value:Dynamic, key:String, maximum:Int, fallback:String = ""):String {
        var input = value == null ? null : Reflect.field(value, key);
        if (input == null) {
            return fallback;
        }
        if (!Std.isOfType(input, String)) {
            throw new Exception("Check the design field: " + key + ".");
        }
        var result:String = input;
        if (result.length > maximum || result.indexOf(String.fromCharCode(0)) >= 0) {
            throw new Exception("Check the design field: " + key + ".");
        }
        return result;
    }

    static function choice(value:Dynamic, key:String, choices:Array<String>,
            fallback:String):String {
        var result = text(value, key, 80, fallback);
        if (!choices.contains(result)) {
            throw new Exception("Choose a supported value for " + key + ".");
        }
        return result;
    }

    static function number(value:Dynamic, key:String, minimum:Int, maximum:Int, fallback:Int):Int {
        var input:Dynamic = value == null ? null : Reflect.field(value, key);
        if (input == null) {
            return fallback;
        }
        if (!Std.isOfType(input, Int) || input < minimum || input > maximum) {
            throw new Exception("Choose a valid number for " + key + ".");
        }
        return input;
    }

    static function color(value:Dynamic, key:String, fallback:String = ""):String {
        var result = text(value, key, 7, fallback);
        if (result != "" && !~/^#[0-9a-fA-F]{6}$/.match(result)) {
            throw new Exception("Choose a valid color for " + key + ".");
        }
        return result;
    }

    function identifier(value:Dynamic):String {
        var id = text(value, "id", 40);
        nodes++;
        if (!~/^[A-Za-z0-9_-]{1,40}$/.match(id) || identifiers.exists(id)) {
            throw new Exception("Every section and block needs a unique identifier.");
        }
        if (nodes > ThemeDesignSchema.MAX_NODES) {
            throw new Exception("This design exceeds the 2048 node document limit.");
        }
        identifiers.set(id, true);
        return id;
    }

    static function list(value:Dynamic, label:String, maximum:Int):Array<Dynamic> {
        if (!Std.isOfType(value, Array)) {
            throw new Exception(label + " must be a list.");
        }
        var entries:Array<Dynamic> = value;
        if (entries.length > maximum) {
            throw new Exception(label + " contains too many entries.");
        }
        return entries;
    }

    static function safeLink(value:String):Void {
        if (value != ""
            && (!~/^(\/(?!\/)|#[A-Za-z]|https?:\/\/|mailto:|tel:)/.match(value)
                || ~/[\x00-\x20\x7f\\]/.match(value))) {
            throw new Exception("Use an internal path or a valid web, email or phone link.");
        }
    }

    static function binding(value:String):Void {
        if (value != ""
            && (!~/^(site|item|collection|page)(\.[A-Za-z_][A-Za-z0-9_]*){1,5}$/.match(value)
                || ~/(^|\.)(__proto__|prototype|constructor)(\.|$)/.match(value))) {
            throw new Exception("Choose a public CMS field for this binding.");
        }
    }

    static function styles(value:Dynamic):Dynamic {
        var result:Dynamic = {};
        if (value == null) {
            return result;
        }
        object(value, "Styles");
        for (breakpoint in Reflect.fields(value)) {
            if (!["desktop", "tablet", "mobile"].contains(breakpoint)) {
                throw new Exception("Choose a supported style breakpoint.");
            }
            var states = object(Reflect.field(value, breakpoint), "Breakpoint styles");
            var device:Dynamic = {};
            for (state in Reflect.fields(states)) {
                if (!["normal", "hover", "focus"].contains(state)) {
                    throw new Exception("Choose a supported interaction state.");
                }
                var input = object(Reflect.field(states, state), "Style declarations");
                if (Reflect.fields(input).length > 100) {
                    throw new Exception("Use at most 100 declarations in each style state.");
                }
                var declarations:Dynamic = {};
                for (property in Reflect.fields(input)) {
                    if (!~/^(--[a-zA-Z][a-zA-Z0-9-]*|-?[a-z][a-z0-9-]*)$/.match(property)
                        || property.length > 64
                        || ["behavior", "-moz-binding"].contains(property)) {
                        throw new Exception("Choose a valid CSS property.");
                    }
                    var propertyValue = text(input, property, 2000);
                    if (~/[{};<>]/.match(propertyValue)) {
                        throw new Exception("Enter a CSS value, without a rule or declaration separator.");
                    }
                    propertyValue = ThemeCss.validate(propertyValue);
                    if (propertyValue != "") {
                        Reflect.setField(declarations, property, propertyValue);
                    }
                }
                Reflect.setField(device, state, declarations);
            }
            Reflect.setField(result, breakpoint, device);
        }
        return result;
    }

    static function classNames(value:Dynamic):Array<String> {
        if (value == null) {
            return [];
        }
        return list(value, "Classes", 64).map(entry -> {
            if (!Std.isOfType(entry, String) || !~/^[A-Za-z_][A-Za-z0-9_:-]{0,79}$/.match(entry)) {
                throw new Exception("Use a class name with lowercase letters, numbers and hyphens.");
            }
            return cast entry;
        });
    }

    function blocks(input:Dynamic, depth:Int):Array<Dynamic> {
        var entries = list(input, "Blocks", 256);
        if (entries.length == 0) {
            return [];
        }
        if (depth > ThemeDesignSchema.MAX_DEPTH) {
            throw new Exception("This design exceeds the 16 level nesting limit.");
        }
        return entries.map(node -> {
            object(node, "Block");
            var id = identifier(node);
            var kind = choice(node, "type", ThemeDesignSchema.blockTypes, "text");
            var href = text(node, "href", 500);
            safeLink(href);
            var image = text(node, "image", 500);
            if (image != "" && !(MediaReferences.imageUrl(image) || ThemeAssets.imageUrl(image))) {
                throw new Exception("Choose uploaded images from this theme or the media library.");
            }
            var children = blocks(node.children ?? [], depth + 1);
            if (children.length > 0 && !["container", "element", "repeat"].contains(kind)) {
                throw new Exception("Only containers, HTML elements and repeaters can contain blocks.");
            }
            var tag = choice(node, "tag", tags, "div");
            if (["input", "br", "hr"].contains(tag) && children.length > 0) {
                throw new Exception("This HTML element cannot contain children.");
            }
            var values:Dynamic = {};
            var attributesInput = node.attributes == null ? {} : object(node.attributes,
                "HTML attributes");
            if (Reflect.fields(attributesInput).length > 32) {
                throw new Exception("Use at most 32 HTML attributes on an element.");
            }
            for (key in Reflect.fields(attributesInput)) {
                if (!attributes.contains(key) && !~/^(aria|data)-[a-z][a-z0-9-]{0,40}$/.match(key)) {
                    throw new Exception("This HTML attribute is not supported: " + key + ".");
                }
                var attributeValue = text(attributesInput,
                    key, key == "d" || key == "points" ? 32000 : 2000);
                if (["fill", "stroke", "clip-path", "clipPath"].contains(key)) {
                    attributeValue = ThemeCss.validate(attributeValue);
                }
                if (key == "action") {
                    safeLink(attributeValue);
                    if (attributeValue != ""
                        && (!StringTools.startsWith(attributeValue, "/")
                            || StringTools.startsWith(attributeValue, "//"))) {
                        throw new Exception("Forms must submit to a CMS route.");
                    }
                }
                Reflect.setField(values, key, attributeValue);
            }
            var bindings:Dynamic = {};
            var bindingsInput = node.bindings == null ? {} : object(node.bindings, "Data bindings");
            for (key in Reflect.fields(bindingsInput)) {
                if (!["text", "href", "image", "alt", "value", "datetime"].contains(key)) {
                    throw new Exception("Choose a supported bindable property.");
                }
                var path = text(bindingsInput, key, 120);
                binding(path);
                Reflect.setField(bindings, key, path);
            }
            var condition:Dynamic = null;
            if (node.condition != null) {
                var field = text(node.condition, "field", 120);
                binding(field);
                condition = {field: field, value: text(node.condition, "value", 500)};
                Reflect.setField(condition, "operator",
                    choice(node.condition, "operator", ["present", "empty", "equals"], "present"));
            }
            var component = text(node, "component", 40);
            if (kind == "component") {
                references.push(component);
            }
            var source = text(node, "source", 80, "page.items");
            if (!~/^(page\.(items|related)|feed:[a-zA-Z0-9_-]{1,40})$/.match(source)) {
                throw new Exception("Choose a current-page list or a named content source.");
            }
            if (kind == "repeat" && StringTools.startsWith(source, "feed:")) {
                sourceReferences.push(source.substr(5));
            }
            var slot = text(node, "slot", 80);
            if (slot != "" && !~/^[a-z][a-z0-9_.-]{0,79}$/.match(slot)) {
                throw new Exception("Choose a valid plugin slot name.");
            }
            return {
                id: id,
                type: kind,
                name: text(node, "name", 80),
                text: text(node, "text", 16000),
                href: href,
                image: image,
                alt: text(node, "alt", 240),
                level: number(node, "level", 1, 6, 2),
                tag: tag,
                children: children,
                styles: styles(node.styles),
                classes: classNames(node.classes),
                attributes: values,
                bindings: bindings,
                source: source,
                component: component,
                slot: slot,
                condition: condition
            };
        });
    }

    function sections(value:Dynamic):Array<Dynamic> {
        return list(value, "Sections", 128).map(section -> {
            object(section, "Section");
            var id = identifier(section);
            return {
                id: id,
                name: text(section, "name", 80),
                background: color(section, "background"),
                color: color(section, "color"),
                padding: number(section, "padding", 0, 2000, 48),
                columns: number(section, "columns", 1, 24, 1),
                align: choice(section, "align", ["left", "center", "right"], "left"),
                width: choice(section, "width", ["content", "wide", "full"], "content"),
                blocks: blocks(section.blocks ?? [], 1),
                styles: styles(section.styles),
                classes: classNames(section.classes)
            };
        });
    }

    public function validate(input:Dynamic):Dynamic {
        object(input, "Theme design");
        if (input.schema != 1 && input.schema != 2) {
            throw new Exception("This theme design version is not supported.");
        }
        var tokens = object(input.tokens, "Design tokens");
        var font = text(tokens, "font", 200, "sans");
        if (!~/^[A-Za-z0-9 ,"'-]+$/.match(font)) {
            throw new Exception("Enter a font family name or font stack.");
        }
        var header = sections(input.header);
        var footer = sections(input.footer);
        var pages:Dynamic = {};
        var metadata:Dynamic = {};
        var rawTemplates = object(input.templates, "Templates");
        var names = Reflect.fields(rawTemplates);
        if (names.length > 32) {
            throw new Exception("Use at most 32 templates in a theme.");
        }
        for (name in ThemeDesignSchema.templates) {
            if (!names.contains(name)) {
                throw new Exception("Keep every core CMS template in this theme.");
            }
        }
        for (name in names) {
            if (!~/^[A-Za-z][A-Za-z0-9_-]{0,79}$/.match(name)
                || StringTools.startsWith(name, "Admin")) {
                throw new Exception("Choose a public template name with letters, numbers, hyphens and underscores.");
            }
            Reflect.setField(pages, name, sections(Reflect.field(rawTemplates, name)));
            if (!ThemeDesignSchema.templates.contains(name)) {
                var declared = input.templateMeta == null ? null : Reflect.field(input.templateMeta,
                    name);
                Reflect.setField(metadata, name, {
                    label: text(declared, "label", 80, name),
                    fallback: choice(declared, "fallback", ThemeDesignSchema.templates, "Page")
                });
            }
        }
        var components:Dynamic = {};
        var rawComponents = input.components == null ? {} : object(input.components, "Components");
        if (Reflect.fields(rawComponents).length > 32) {
            throw new Exception("Use at most 32 reusable components.");
        }
        for (id in Reflect.fields(rawComponents)) {
            if (!~/^[a-zA-Z0-9_-]{1,40}$/.match(id)) {
                throw new Exception("Choose a valid component identifier.");
            }
            var component = Reflect.field(rawComponents, id);
            Reflect.setField(components, id, {
                name: text(component, "name", 80, "Component"),
                sections: sections(component.sections)
            });
        }
        for (id in references) {
            if (!Reflect.hasField(components, id)) {
                throw new Exception("A reusable component is missing from this design.");
            }
        }
        var classes:Dynamic = {};
        var rawClasses = input.classes == null ? {} : object(input.classes, "Classes");
        if (Reflect.fields(rawClasses).length > 64) {
            throw new Exception("Use at most 64 reusable style classes.");
        }
        for (name in Reflect.fields(rawClasses)) {
            if (!~/^[a-z][a-z0-9-]{0,39}$/.match(name)) {
                throw new Exception("Choose a valid style class name.");
            }
            Reflect.setField(classes, name, styles(Reflect.field(rawClasses, name)));
        }
        var feedIds:Map<String, Bool> = [];
        var feeds = list(input.feeds ?? [], "Content sources", 8).map(feed -> {
            var id = text(feed, "id", 40);
            if (!~/^[a-zA-Z0-9_-]{1,40}$/.match(id) || feedIds.exists(id)) {
                throw new Exception("Each content source needs a unique identifier.");
            }
            feedIds.set(id, true);
            return {
                id: id,
                name: text(feed, "name", 80),
                collection: text(feed, "collection", 32),
                limit: number(feed, "limit", 1, 24, 6),
                category: text(feed, "category", 80),
                tag: text(feed, "tag", 120),
                query: text(feed, "query", 120),
                order: choice(feed, "order", ["published_at", "title", "id"], "published_at"),
                direction: choice(feed, "direction", ["ASC", "DESC"], "DESC")
            };
        });
        for (source in sourceReferences) {
            if (!feedIds.exists(source)) {
                throw new Exception("A repeater refers to a missing content source.");
            }
        }
        var css = text(input, "css", 64000);
        css = ThemeCss.validate(css, true);
        var result = {
            schema: 2,
            tokens: {
                background: color(tokens, "background", "#ffffff"),
                text: color(tokens, "text", "#1d2939"),
                accent: color(tokens, "accent", "#3456c4"),
                font: font,
                width: number(tokens, "width", 240, 3840, 1120),
                radius: number(tokens, "radius", 0, 200, 8)
            },
            header: header,
            footer: footer,
            templates: pages,
            templateMeta: metadata,
            components: components,
            classes: classes,
            feeds: feeds,
            css: css
        };
        for (name in names) {
            var total = expanded(header, components, [], 0)
                + expanded(Reflect.field(pages, name), components, [], 0)
                + expanded(footer, components, [], 0);
            if (total > 20000) {
                throw new Exception("Reduce the number of repeated or reusable elements in this template.");
            }
        }
        for (id in Reflect.fields(components)) {
            expanded(Reflect.field(components, id).sections, components, [id], 0);
        }
        return result;
    }

    static function expanded(sections:Array<Dynamic>, components:Dynamic, ancestors:Array<String>,
            depth:Int):Int {
        var count = sections.length;
        for (section in sections) {
            count += expandedBlocks(section.blocks, components, ancestors, depth + 1);
        }
        return count;
    }

    static function expandedBlocks(blocks:Array<Dynamic>, components:Dynamic,
            ancestors:Array<String>, depth:Int):Int {
        if (depth > 32) {
            throw new Exception("Reusable components nest too deeply.");
        }
        var count = blocks.length;
        for (block in blocks) {
            if (block.type == "component") {
                if (ancestors.contains(block.component)) {
                    throw new Exception("Reusable components cannot contain themselves, directly or indirectly.");
                }
                count += expanded(Reflect.field(components, block.component).sections, components,
                    ancestors.concat([block.component]), depth + 1);
            }
            var multiplier = block.type == "repeat" ? 24 : 1;
            count += multiplier * expandedBlocks(block.children, components, ancestors, depth + 1);
            if (count > 20000) {
                throw new Exception("Reduce the number of repeated or reusable elements in this template.");
            }
        }
        return count;
    }
}
