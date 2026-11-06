package hx.press.view;

/**
    The stylesheet of a visual design: style classes, section and block
    rules per breakpoint and interaction, and the design's own CSS scoped to
    `.hp-design`, as the former browser renderer generated it. Values were
    validated when the design was saved.
**/
class DesignStyles {
    static final breakpoints = ["desktop", "tablet", "mobile"];
    static final interactions = ["normal", "hover", "focus"];
    static final identifier = ~/^[A-Za-z0-9_-]{1,80}$/;

    public static function css(document:Dynamic):String {
        var output = new StringBuf();
        if (document == null) {
            return "";
        }
        var classes:Dynamic = document.classes;
        if (classes != null) {
            for (name in Reflect.fields(classes)) {
                if (identifier.match(name)) {
                    output.add(rules('.hp-design .design-class-${name}',
                        Reflect.field(classes, name)));
                }
            }
        }
        for (sections in scopes(document)) {
            for (section in sections) {
                var id = Std.string(section.id);
                if (!identifier.match(id)) {
                    continue;
                }
                var base = new StringBuf();
                base.add('padding-block:${number(section.padding)}px;');
                var align = Std.string(section.align);
                base.add('text-align:${["left", "center", "right"].indexOf(align) >= 0 ? align : "left"};');
                if (section.background != null && section.background != "") {
                    base.add('background:${section.background};');
                }
                if (section.color != null && section.color != "") {
                    base.add('color:${section.color};');
                }
                output.add('.hp-design :where([data-design-node="${id}"]){${base.toString()}}');
                output.add(rules('.hp-design [data-design-node="${id}"]', section.styles));
                visit(section.blocks, node -> {
                    var nodeId = Std.string(node.id);
                    if (identifier.match(nodeId)) {
                        output.add(rules('.hp-design [data-design-node="${nodeId}"]', node.styles));
                    }
                });
            }
        }
        if (document.css != null && document.css != "") {
            output.add('@scope (.hp-design){${document.css}}');
        }
        return output.toString();
    }

    static function scopes(document:Dynamic):Array<Array<Dynamic>> {
        var result:Array<Array<Dynamic>> = [];
        if (document.header != null) {
            result.push(document.header);
        }
        if (document.footer != null) {
            result.push(document.footer);
        }
        if (document.templates != null) {
            for (name in Reflect.fields(document.templates)) {
                result.push(Reflect.field(document.templates, name));
            }
        }
        if (document.components != null) {
            for (name in Reflect.fields(document.components)) {
                var component:Dynamic = Reflect.field(document.components, name);
                if (component != null && component.sections != null) {
                    result.push(component.sections);
                }
            }
        }
        return result;
    }

    static function visit(blocks:Dynamic, action:Dynamic->Void):Void {
        if (blocks == null) {
            return;
        }
        var list:Array<Dynamic> = blocks;
        for (node in list) {
            action(node);
            visit(node.children, action);
        }
    }

    static function rules(selector:String, styles:Dynamic):String {
        if (styles == null) {
            return "";
        }
        var css = new StringBuf();
        for (breakpoint in breakpoints) {
            var device = new StringBuf();
            var states:Dynamic = Reflect.field(styles, breakpoint);
            if (states == null) {
                continue;
            }
            for (interaction in interactions) {
                var values:Dynamic = Reflect.field(states, interaction);
                if (values == null || Reflect.fields(values).length == 0) {
                    continue;
                }
                var suffix = interaction == "normal" ? "" : interaction == "focus" ? ":focus-visible" : ":hover";
                device.add('${selector}${suffix}{${declarations(values)}}');
            }
            var text = device.toString();
            if (breakpoint == "desktop") {
                css.add(text);
            } else if (text != "") {
                css.add('@media(max-width:${breakpoint == "tablet" ? 900 : 600}px){${text}}');
            }
        }
        return css.toString();
    }

    static function declarations(values:Dynamic):String {
        var output = new StringBuf();
        for (property in Reflect.fields(values)) {
            output.add('${property}:${Reflect.field(values, property)};');
        }
        return output.toString();
    }

    static function number(value:Dynamic):Int {
        if (value == null) {
            return 0;
        }
        var parsed = Std.parseFloat(Std.string(value));
        return Math.isFinite(parsed) ? Std.int(parsed) : 0;
    }
}
