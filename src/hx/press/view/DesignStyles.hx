package hx.press.view;

/**
    The stylesheet of a visual design: style classes, section and block
    rules per breakpoint and interaction, and the design's own CSS scoped to
    `.hp-design`, as the former browser renderer generated it. Values were
    validated when the design was saved.

    Every desktop rule comes first, then one tablet and one mobile media
    block, so tablet overrides desktop and mobile overrides both whichever
    class or node a rule belongs to. Inside each block classes precede
    sections and blocks, and names and properties are sorted, so the output
    matches the editor preview (`resources/js/themes/builder/styles.ts`).
**/
class DesignStyles {
    static final breakpoints = ["desktop", "tablet", "mobile"];
    static final interactions = ["normal", "hover", "focus"];
    static final identifier = ~/^[A-Za-z0-9_-]{1,80}$/;

    public static function css(document:Dynamic):String {
        if (document == null) {
            return "";
        }
        var layers = [new StringBuf(), new StringBuf(), new StringBuf()];
        var classes:Dynamic = document.classes;
        if (classes != null) {
            for (name in sorted(classes)) {
                if (identifier.match(name)) {
                    rules(layers, '.hp-design .design-class-${name}', Reflect.field(classes, name));
                }
            }
        }
        var desktop = layers[0];
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
                desktop.add('.hp-design :where([data-design-node="${id}"]){${base.toString()}}');
                rules(layers, '.hp-design [data-design-node="${id}"]', section.styles);
                visit(section.blocks, node -> {
                    var nodeId = Std.string(node.id);
                    if (identifier.match(nodeId)) {
                        rules(layers, '.hp-design [data-design-node="${nodeId}"]', node.styles);
                    }
                });
            }
        }
        var output = new StringBuf();
        output.add(desktop.toString());
        var tablet = layers[1].toString();
        if (tablet != "") {
            output.add('@media(max-width:900px){${tablet}}');
        }
        var mobile = layers[2].toString();
        if (mobile != "") {
            output.add('@media(max-width:600px){${mobile}}');
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
            for (name in sorted(document.templates)) {
                result.push(Reflect.field(document.templates, name));
            }
        }
        if (document.components != null) {
            for (name in sorted(document.components)) {
                var component:Dynamic = Reflect.field(document.components, name);
                if (component != null && component.sections != null) {
                    result.push(component.sections);
                }
            }
        }
        return result;
    }

    /** The field names of a record in code-unit order, which `Reflect.fields` does not guarantee. **/
    static function sorted(record:Dynamic):Array<String> {
        var names = Reflect.fields(record);
        names.sort((left, right) -> left < right ? -1 : left > right ? 1 : 0);
        return names;
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

    /** Adds a selector's rules to the desktop, tablet and mobile layers. **/
    static function rules(layers:Array<StringBuf>, selector:String, styles:Dynamic):Void {
        if (styles == null) {
            return;
        }
        for (index in 0...breakpoints.length) {
            var states:Dynamic = Reflect.field(styles, breakpoints[index]);
            if (states == null) {
                continue;
            }
            for (interaction in interactions) {
                var values:Dynamic = Reflect.field(states, interaction);
                if (values == null || Reflect.fields(values).length == 0) {
                    continue;
                }
                var suffix = interaction == "normal" ? "" : interaction == "focus" ? ":focus-visible" : ":hover";
                layers[index].add('${selector}${suffix}{${declarations(values)}}');
            }
        }
    }

    static function declarations(values:Dynamic):String {
        var output = new StringBuf();
        for (property in sorted(values)) {
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
