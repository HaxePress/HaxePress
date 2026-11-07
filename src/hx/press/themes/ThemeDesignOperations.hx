package hx.press.themes;

import haxe.Exception;
import hx.press.themes.ThemeDesignModel.DesignSelection;

/**
    The atomic design edits of the MCP `edit_design` tool, the operations
    of the visual editor: insert, section, update, style, move, remove,
    duplicate, tokens and css. They change the document in place and stop
    at the first invalid operation; the caller saves nothing in that case.
**/
class ThemeDesignOperations {
    static final blockFields = [
        "name",
        "text",
        "href",
        "image",
        "alt",
        "level",
        "tag",
        "classes",
        "attributes",
        "bindings",
        "source",
        "component",
        "slot",
        "condition",
        "styles",
        "children"
    ];
    static final sectionFields = [
        "name",
        "background",
        "color",
        "padding",
        "columns",
        "align",
        "width",
        "classes",
        "styles"
    ];
    static final tokenFields = ["background", "text", "accent", "font", "width", "radius"];
    static final reserved = ["__proto__", "prototype", "constructor"];

    static function assign(target:Dynamic, values:Null<Dynamic>, allowed:Array<String>):Void {
        if (values == null) {
            return;
        }
        for (key in Reflect.fields(values)) {
            if (!allowed.contains(key) || reserved.contains(key)) {
                throw new Exception('Unsupported field: ${key}');
            }
            Reflect.setField(target, key, Reflect.field(values, key));
        }
    }

    static function selection(value:Dynamic):Null<DesignSelection> {
        if (value == null) {
            return null;
        }
        var block:Null<String> = value.block;
        return {scope: value.scope, section: value.section, block: block};
    }

    static function hasBlock(target:DesignSelection):Bool {
        return target.block != null && target.block != "";
    }

    /** Applies `operations` to `document` and returns the selections of the nodes they created. **/
    public static function apply(document:Dynamic, operations:Array<Dynamic>):Array<Dynamic> {
        var created:Array<Dynamic> = [];
        for (operation in operations) {
            var action:String = operation.action;
            if (action == "tokens") {
                assign(document.tokens, operation.values, tokenFields);
                continue;
            }
            if (action == "css") {
                document.css = operation.text ?? "";
                continue;
            }
            var target = selection(operation.target);
            if (target == null || !ThemeDesignModel.scopesFor(document).contains(target.scope)) {
                throw new Exception("Choose an existing design scope.");
            }
            var sections = ThemeDesignModel.sectionsFor(document, target.scope);
            var selected = ThemeDesignModel.selectionFor(document, target);
            if (action == "section") {
                var preset:Null<String> = operation.preset;
                var name:Null<String> = operation.name;
                if (preset != null && preset != "" && !ThemeDesignModel.readySection(preset)) {
                    throw new Exception("Choose a supported ready section.");
                }
                var section = preset != null
                    && preset != "" ? ThemeDesignModel.friendlySection(preset) : ThemeDesignModel.newSection(name != null
                        && name != "" ? name : "Section");
                if (name != null && name != "") {
                    section.name = name;
                }
                var index = ThemeDesignModel.sectionIndex(sections, target.section);
                sections.insert(index < 0 ? sections.length : index + 1, section);
                created.push({scope: target.scope, section: section.id});
                continue;
            }
            if (selected.section == null || (hasBlock(target) && selected.block == null)) {
                throw new Exception("The selected design element no longer exists.");
            }
            switch (action) {
                case "insert":
                    insert(operation, target, selected, created);
                case "update":
                    var node:Dynamic = selected.block ?? selected.section;
                    assign(node, operation.values,
                        selected.block != null ? blockFields : sectionFields);
                case "style":
                    style(operation, selected.block ?? selected.section);
                case "move":
                    var destination = selection(operation.destination);
                    var position:String = operation.destination?.position ?? "before";
                    if (destination == null
                        || !ThemeDesignModel.moveDesignEntry(document, target, destination,
                            position)) {
                        throw new Exception("This move is invalid or would create a cycle.");
                    }
                case "remove" | "duplicate":
                    removeOrDuplicate(action, target, sections, selected.section, created);
                default:
            }
        }
        return created;
    }

    static function insert(operation:Dynamic, target:DesignSelection,
            selected:{section:Null<Dynamic>, block:Null<Dynamic>}, created:Array<Dynamic>):Void {
        var preset:String = operation.preset != null
            && operation.preset != "" ? operation.preset : "text";
        var layout = StringTools.startsWith(preset, "layout:");
        var supported = layout ? ThemeDesignModel.layoutIds.contains(preset.substr(7)) : ThemeDesignModel.blockTypes.contains(preset);
        if (!supported) {
            throw new Exception("Choose a supported element or layout.");
        }
        var node = layout ? ThemeDesignModel.layoutBlock(preset.substr(7)) : ThemeDesignModel.newBlock(preset);
        assign(node, operation.values, blockFields);
        if (selected.block != null && ThemeDesignModel.canContain(selected.block)) {
            if (selected.block.children == null) {
                selected.block.children = [];
            }
            (selected.block.children : Array<Dynamic>).push(node);
        } else if (hasBlock(target)) {
            var location = ThemeDesignModel.findBlockLocation(selected.section.blocks,
                target.block);
            location.list.insert(location.index + 1, node);
        } else {
            (selected.section.blocks : Array<Dynamic>).push(node);
        }
        created.push({scope: target.scope, section: target.section, block: node.id});
    }

    static function style(operation:Dynamic, node:Dynamic):Void {
        var values:Dynamic = operation.values ?? {};
        var breakpoint:String = operation.breakpoint ?? "desktop";
        var state:String = operation.state ?? "normal";
        for (property in Reflect.fields(values)) {
            var value:Dynamic = Reflect.field(values, property);
            if (reserved.contains(property)) {
                throw new Exception("Choose a valid CSS property.");
            }
            if (!Std.isOfType(value, String)) {
                throw new Exception("CSS values must be strings.");
            }
            if (node.styles == null) {
                node.styles = {};
            }
            ThemeDesignModel.setStyle(node.styles, breakpoint, state, property, value);
        }
    }

    static function removeOrDuplicate(action:String, target:DesignSelection,
            sections:Array<Dynamic>, section:Dynamic, created:Array<Dynamic>):Void {
        if (hasBlock(target)) {
            var location = ThemeDesignModel.findBlockLocation(section.blocks, target.block);
            if (action == "remove") {
                location.list.splice(location.index, 1);
            } else {
                var copy = ThemeDesignModel.cloneBlock(location.list[location.index]);
                location.list.insert(location.index + 1, copy);
                created.push({scope: target.scope, section: target.section, block: copy.id});
            }
            return;
        }
        var index = ThemeDesignModel.sectionIndex(sections, target.section);
        if (action == "remove") {
            sections.splice(index, 1);
        } else {
            var copy = ThemeDesignModel.cloneSection(section);
            sections.insert(index + 1, copy);
            created.push({scope: target.scope, section: copy.id});
        }
    }
}
