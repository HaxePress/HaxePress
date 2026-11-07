package hx.press.themes;

import haxe.Json;
import hx.well.internal.SecureToken;

typedef DesignSelection = {
    var scope:String;
    var section:String;
    var ?block:String;
}

typedef DesignLocation = {
    var list:Array<Dynamic>;
    var index:Int;
    var parent:Null<Dynamic>;
}

/**
    The theme document helpers and ready-made layouts the visual editor
    uses (`resources/js/themes/builder/types.ts`, `presets.ts` and
    `friendly-presets.ts`), for the MCP design tools. Documents are the JSON
    values the design API returns; the CMS validates every saved document.
**/
class ThemeDesignModel {
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

    public static final htmlTags = [
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

    /** Element tags that never own child blocks. **/
    static final leafTags = [
        "input",
        "br",
        "hr",
        "p",
        "span",
        "a",
        "strong",
        "em",
        "small",
        "h1",
        "h2",
        "h3",
        "h4",
        "h5",
        "h6",
        "button",
        "textarea",
        "select",
        "option",
        "time",
        "code",
        "path",
        "circle",
        "ellipse",
        "rect",
        "line",
        "polyline",
        "polygon",
        "stop",
        "text"
    ];

    /** Layout presets with their labels, in the order the editor lists them. **/
    public static final layoutIds = ["container", "row", "column", "grid", "hero", "split", "cards", "spacer"];

    public static final layoutLabels:Map<String, String> = [
        "container" => "Container",
        "row" => "Row",
        "column" => "Column",
        "grid" => "Grid",
        "hero" => "Hero",
        "split" => "Image and text",
        "cards" => "Content cards",
        "spacer" => "Space"
    ];

    /** Ready sections with their names, in the order the editor lists them. **/
    public static final sectionChoices = [
        {id: "welcome", name: "Introduction"},
        {id: "split", name: "Image and text"},
        {id: "highlights", name: "Highlights"},
        {id: "content", name: "Latest content"},
        {id: "callout", name: "Call to action"},
        {id: "questions", name: "Questions and answers"},
        {id: "contact", name: "Contact details"},
        {id: "empty", name: "Empty section"}
    ];

    /** The layout presets as the design guide publishes them: an ID-to-label object. **/
    public static function layouts():Dynamic {
        var result:Dynamic = {};
        for (id in layoutIds) {
            Reflect.setField(result, id, layoutLabels.get(id));
        }
        return result;
    }

    /** A random version 4 UUID, as `crypto.randomUUID()` creates for new nodes. **/
    public static function newId():String {
        var alphabet = "_-0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";
        var hex = "0123456789abcdef";
        var token = SecureToken.generate(32);
        var digits = new StringBuf();
        for (index in 0...32) {
            var value = alphabet.indexOf(token.charAt(index)) & 15;
            if (index == 12) {
                value = 4;
            } else if (index == 16) {
                value = 8 | (value & 3);
            }
            digits.add(hex.charAt(value));
        }
        var text = digits.toString();
        return
            '${text.substr(0, 8)}-${text.substr(8, 4)}-${text.substr(12, 4)}-${text.substr(16, 4)}-${text.substr(20)}';
    }

    public static function copy(value:Dynamic):Dynamic {
        return Json.parse(Json.stringify(value));
    }

    public static function canContain(block:Dynamic):Bool {
        if (block.type == "container" || block.type == "repeat") {
            return true;
        }
        var tag:String = block.tag == null || block.tag == "" ? "div" : block.tag;
        return block.type == "element" && !leafTags.contains(tag);
    }

    public static function scopesFor(document:Dynamic):Array<String> {
        var scopes = ["header", "footer"];
        for (name in Reflect.fields(document.templates)) {
            scopes.push(name);
        }
        if (document.components != null) {
            for (id in Reflect.fields(document.components)) {
                scopes.push('@${id}');
            }
        }
        return scopes;
    }

    public static function sectionsFor(document:Dynamic, scope:String):Array<Dynamic> {
        if (scope == "header" || scope == "footer") {
            return Reflect.field(document, scope);
        }
        if (StringTools.startsWith(scope, "@")) {
            var component:Dynamic = document.components == null ? null : Reflect.field(document.components,
                scope.substr(1));
            return component == null || component.sections == null ? [] : component.sections;
        }
        var sections:Null<Array<Dynamic>> = Reflect.field(document.templates, scope);
        return sections ?? [];
    }

    static function children(block:Dynamic):Array<Dynamic> {
        return block.children == null ? [] : block.children;
    }

    public static function findBlock(blocks:Array<Dynamic>, id:Null<String>):Null<Dynamic> {
        if (id == null || id == "") {
            return null;
        }
        for (block in blocks) {
            if (block.id == id) {
                return block;
            }
            var found = findBlock(children(block), id);
            if (found != null) {
                return found;
            }
        }
        return null;
    }

    public static function findBlockLocation(blocks:Array<Dynamic>,
            id:String):Null<DesignLocation> {
        for (index in 0...blocks.length) {
            if (blocks[index].id == id) {
                return {list: blocks, index: index, parent: null};
            }
        }
        for (block in blocks) {
            var found = findBlockLocation(children(block), id);
            if (found != null) {
                return {list: found.list, index: found.index, parent: found.parent ?? block};
            }
        }
        return null;
    }

    public static function findSection(sections:Array<Dynamic>, id:String):Null<Dynamic> {
        return Lambda.find(sections, section -> section.id == id);
    }

    public static function sectionIndex(sections:Array<Dynamic>, id:String):Int {
        for (index in 0...sections.length) {
            if (sections[index].id == id) {
                return index;
            }
        }
        return -1;
    }

    public static function selectionFor(document:Dynamic,
            selection:DesignSelection):{section:Null<Dynamic>, block:Null<Dynamic>} {
        var section = findSection(sectionsFor(document, selection.scope), selection.section);
        var blocks:Array<Dynamic> = section == null ? [] : section.blocks;
        return {section: section, block: findBlock(blocks, selection.block)};
    }

    public static function cloneBlock(block:Dynamic):Dynamic {
        var result:Dynamic = copy(block);
        result.id = newId();
        result.children = [for (child in children(block)) cloneBlock(child)];
        return result;
    }

    public static function cloneSection(section:Dynamic):Dynamic {
        var result:Dynamic = copy(section);
        result.id = newId();
        var blocks:Array<Dynamic> = section.blocks;
        result.blocks = [for (block in blocks) cloneBlock(block)];
        return result;
    }

    public static function newBlock(type:String):Dynamic {
        var text = switch (type) {
            case "heading": "Your heading";
            case "text": "Add your text here.";
            case "button": "Learn more";
            default: "";
        };
        return {
            id: newId(),
            type: type,
            text: text,
            href: type == "button" ? "/" : "",
            image: "",
            alt: "",
            level: 2,
            name: "",
            children: [],
            tag: "div",
            styles: {},
            bindings: {},
            attributes: {},
            classes: [],
            source: "page.items"
        };
    }

    public static function newSection(name:String = "Section"):Dynamic {
        return {
            id: newId(),
            name: name,
            background: "",
            color: "",
            padding: 48,
            columns: 1,
            align: "left",
            width: "content",
            blocks: [],
            styles: {},
            classes: []
        };
    }

    /** Sets one CSS property for a breakpoint and state; an empty value removes it. **/
    public static function setStyle(styles:Dynamic, breakpoint:String, interaction:String,
            property:String, value:String):Void {
        var device:Dynamic = Reflect.field(styles, breakpoint);
        if (device == null) {
            device = {};
            Reflect.setField(styles, breakpoint, device);
        }
        var state:Dynamic = Reflect.field(device, interaction);
        if (state == null) {
            state = {};
            Reflect.setField(device, interaction, state);
        }
        if (value == "") {
            Reflect.deleteField(state, property);
        } else {
            Reflect.setField(state, property, value);
        }
    }

    /** Moves owned design nodes, including into containers, without introducing cycles. **/
    public static function moveDesignEntry(document:Dynamic, source:DesignSelection,
            target:DesignSelection, position:String):Bool {
        var scopes = scopesFor(document);
        if (!scopes.contains(source.scope) || !scopes.contains(target.scope)) {
            return false;
        }
        var from = sectionsFor(document, source.scope);
        var to = sectionsFor(document, target.scope);
        if (source.block == null || source.block == "") {
            if ((target.block != null && target.block != "")
                || (source.scope == target.scope && source.section == target.section)) {
                return false;
            }
            var index = sectionIndex(from, source.section);
            if (index < 0) {
                return false;
            }
            var section = from.splice(index, 1)[0];
            var destination = sectionIndex(to, target.section);
            var insertAt = destination < 0 ? to.length : destination
                + (position == "after" ? 1 : 0);
            to.insert(insertAt, section);
            return true;
        }
        var sourceSection = findSection(from, source.section);
        var targetSection = findSection(to, target.section);
        if (sourceSection == null || targetSection == null) {
            return false;
        }
        var sourceLocation = findBlockLocation(sourceSection.blocks, source.block);
        if (sourceLocation == null) {
            return false;
        }
        var node:Dynamic = sourceLocation.list[sourceLocation.index];
        if (source.block == target.block || findBlock(children(node), target.block) != null) {
            return false;
        }
        var targetNode = findBlock(targetSection.blocks, target.block);
        if (position == "inside" && targetNode != null && !canContain(targetNode)) {
            return false;
        }
        sourceLocation.list.splice(sourceLocation.index, 1);
        if (position == "inside" && targetNode != null) {
            if (targetNode.children == null) {
                targetNode.children = [];
            }
            (targetNode.children : Array<Dynamic>).push(node);
        } else if (target.block != null && target.block != "") {
            var destination = findBlockLocation(targetSection.blocks, target.block);
            if (destination == null) {
                sourceLocation.list.insert(sourceLocation.index, node);
                return false;
            }
            destination.list.insert(destination.index + (position == "after" ? 1 : 0), node);
        } else {
            (targetSection.blocks : Array<Dynamic>).push(node);
        }
        return true;
    }

    static function styled(type:String, properties:Dynamic):Dynamic {
        var block = newBlock(type);
        block.styles = {desktop: {normal: properties}};
        return block;
    }

    public static function contentRepeater():Dynamic {
        var repeat = styled("repeat", {
            display: "grid",
            "grid-template-columns": "repeat(3, minmax(0, 1fr))",
            gap: "32px"
        });
        repeat.name = "Content cards";
        repeat.styles.tablet = {normal: {"grid-template-columns": "repeat(2, minmax(0, 1fr))"}};
        repeat.styles.mobile = {normal: {"grid-template-columns": "minmax(0, 1fr)"}};
        var card = styled("container", {display: "flex", "flex-direction": "column", gap: "16px"});
        card.name = "Card";
        var image = styled("image", {
            width: "100%",
            "aspect-ratio": "1.5",
            "object-fit": "cover",
            "border-radius": "8px"
        });
        image.bindings = {image: "item.image", alt: "item.image_alt", href: "item.url"};
        image.condition = {field: "item.image", "operator": "present", value: ""};
        var heading = styled("heading", {"font-size": "24px", "line-height": "1.2"});
        heading.level = 2;
        heading.bindings = {text: "item.title", href: "item.url"};
        var excerpt = styled("text", {"font-size": "15px", "line-height": "1.65"});
        excerpt.bindings = {text: "item.excerpt"};
        var date = styled("element", {"font-size": "12px", opacity: "0.65"});
        date.tag = "time";
        date.bindings = {text: "item.publishedLabel", datetime: "item.published_at"};
        card.children = [image, heading, excerpt, date];
        repeat.children = [card];
        return repeat;
    }

    public static function layoutBlock(preset:String):Dynamic {
        if (preset == "cards") {
            return contentRepeater();
        }
        if (preset == "spacer") {
            return newBlock("spacer");
        }
        var node = styled("container", {display: "flex", "flex-direction": "column", gap: "24px"});
        node.name = layoutLabels.get(preset);
        var base:Dynamic = node.styles.desktop.normal;
        if (preset == "row" || preset == "split") {
            Reflect.setField(base, "flex-direction", "row");
            Reflect.setField(base, "align-items", "center");
            node.styles.mobile = {normal: {"flex-direction": "column", "align-items": "stretch"}};
        }
        if (preset == "grid") {
            var normal:Dynamic = {
                display: "grid",
                "grid-template-columns": "repeat(3, minmax(0, 1fr))",
                gap: "24px"
            };
            node.styles.desktop.normal = normal;
            node.styles.tablet = {normal: {"grid-template-columns": "repeat(2, minmax(0, 1fr))"}};
            node.styles.mobile = {normal: {"grid-template-columns": "minmax(0, 1fr)"}};
            node.children = [
                for (_ in 0...3)
                    styled("container",
                        {"min-height": "120px", padding: "24px", background: "#f4f6fa"})
            ];
        }
        if (preset == "hero") {
            var normal:Dynamic = {
                display: "flex",
                "flex-direction": "column",
                "justify-content": "center",
                "align-items": "flex-start",
                gap: "24px",
                "min-height": "65vh",
                padding: "clamp(32px, 6vw, 100px)",
                background: "#eff3fa",
                "border-radius": "16px"
            };
            node.styles.desktop.normal = normal;
            var heading = newBlock("heading");
            heading.level = 1;
            heading.styles = {
                desktop: {
                    normal: {
                        "font-size": "clamp(40px, 6vw, 80px)",
                        "max-width": "16ch",
                        "line-height": "1.05"
                    }
                }
            };
            var text = newBlock("text");
            text.styles = {desktop: {normal: {"max-width": "60ch", "font-size": "18px"}}};
            node.children = [heading, text, newBlock("button")];
        }
        if (preset == "split") {
            var image = newBlock("image");
            image.styles = {
                desktop: {normal: {width: "50%", "border-radius": "12px"}},
                mobile: {normal: {width: "100%"}}
            };
            var column = layoutBlock("column");
            column.styles.desktop.normal.flex = "1";
            column.children = [newBlock("heading"), newBlock("text"), newBlock("button")];
            node.children = [image, column];
        }
        return node;
    }

    static function textBlock(type:String, text:String, level:Int = 2):Dynamic {
        var node = newBlock(type);
        node.text = text;
        node.level = level;
        return node;
    }

    static function container(name:String, nodes:Array<Dynamic>, styles:Dynamic):Dynamic {
        var node = newBlock("container");
        node.name = name;
        node.children = nodes;
        var normal:Dynamic = {display: "flex", "flex-direction": "column", gap: "20px"};
        for (property in Reflect.fields(styles)) {
            Reflect.setField(normal, property, Reflect.field(styles, property));
        }
        node.styles = {desktop: {normal: normal}};
        return node;
    }

    /** Whether `kind` names a ready section an MCP client may insert. **/
    public static function readySection(kind:String):Bool {
        return kind == "header" || kind == "footer"
            || Lambda.exists(sectionChoices, choice -> choice.id == kind);
    }

    public static function friendlySection(kind:String):Dynamic {
        var choice = Lambda.find(sectionChoices, entry -> entry.id == kind);
        var label = choice != null ? choice.name : (kind == "header" ? "Header" : "Footer");
        var section = newSection(label);
        switch (kind) {
            case "welcome":
                var hero = layoutBlock("hero");
                hero.name = "Introduction";
                hero.styles.desktop.normal.background = "var(--friendly-surface, #eff3ff)";
                Reflect.setField(hero.styles.desktop.normal, "min-height", "420px");
                var parts:Array<Dynamic> = hero.children;
                parts[0].text = "Your title goes here";
                parts[1].text = "Write a short introduction for your visitors.";
                parts[2].text = "Learn more";
                parts[2].href = "/about";
                section.blocks = [hero];
            case "split":
                var split = layoutBlock("split");
                var column:Array<Dynamic> = split.children[1].children;
                column[0].text = "Tell your story";
                column[1].text = "Add a few words about your work, your business or your ideas.";
                column[2].href = "/about";
                section.blocks = [split];
            case "highlights":
                var grid = layoutBlock("grid");
                grid.name = "Highlights";
                grid.children = [
                    for (index in 1...4)
                        container('Highlight ${index}', [
                            textBlock("heading", 'Highlight ${index}', 3),
                            textBlock("text", "Describe one thing your visitors should know.")
                        ], {
                            padding: "28px",
                            background: "#f5f7fb",
                            "border-radius": "12px"
                        })
                ];
                section.blocks = [textBlock("heading", "What you offer"), grid];
            case "content":
                section.blocks = [textBlock("heading", "Latest content"), contentRepeater()];
            case "callout":
                var button = newBlock("button");
                button.text = "Find out more";
                button.href = "/about";
                section.blocks = [
                    container("Call to action", [
                        textBlock("heading", "Add your message"),
                        textBlock("text", "Give your visitors one clear next step."),
                        button
                    ], {
                        padding: "48px",
                        background: "var(--friendly-surface, #eff3ff)",
                        "border-radius": "16px",
                        "align-items": "center",
                        "text-align": "center"
                    })
                ];
            case "questions":
                var blocks:Array<Dynamic> = [textBlock("heading", "Questions and answers")];
                for (index in 1...4) {
                    var details = newBlock("element");
                    details.tag = "details";
                    details.name = 'Question ${index}';
                    details.styles = {
                        desktop: {normal: {padding: "20px 0", "border-bottom": "1px solid #dfe5ee"}}
                    };
                    var summary = newBlock("element");
                    summary.tag = "summary";
                    summary.text = "Add your question";
                    summary.styles = {desktop: {normal: {cursor: "pointer", "font-weight": "600"}}};
                    details.children = [summary, textBlock("text", "Write the answer here.")];
                    blocks.push(details);
                }
                section.blocks = blocks;
            case "contact":
                section.blocks = [
                    textBlock("heading", "Contact"),
                    textBlock("text", "Add your contact details, address or opening hours.")
                ];
            case "empty":
                section.blocks = [
                    textBlock("heading", "Your section title"),
                    textBlock("text", "Add your text here.")
                ];
            case "header":
                section.padding = 24;
                section.columns = 2;
                section.blocks = [newBlock("brand"), newBlock("navigation")];
            case "footer":
                section.padding = 32;
                section.blocks = [newBlock("navigation")];
            default:
        }
        return section;
    }
}
