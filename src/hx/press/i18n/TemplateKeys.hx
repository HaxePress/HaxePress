package hx.press.i18n;

import wellout.check.CheckedTemplate;
import wellout.check.TypedExpr;

/** A literal message key a template translates, with the namespace it names, if any. **/
typedef TemplateKey = {
    var namespace:Null<String>;
    var key:String;
}

/**
    The literal keys of a checked template's `t(key)` and
    `translate(namespace, key)` calls, so the Translations page lists what a
    theme or plugin shows even where its catalogue leaves a key out. A key
    computed from a value, such as `t(link.label)`, is stored text and not
    collected.
**/
class TemplateKeys {
    /**
        The keys of a template. When `components` is given, the names of the
        components the template calls are added to it.
    **/
    public static function collect(template:CheckedTemplate,
            ?components:Array<String>):Array<TemplateKey> {
        var found:Array<TemplateKey> = [];
        var seen:Map<String, Bool> = [];
        var add = (namespace:Null<String>, key:String) -> {
            var identity = '${namespace ?? ""}\n${key}';
            if (!seen.exists(identity)) {
                seen.set(identity, true);
                found.push({namespace: namespace, key: key});
            }
        };
        for (prop in template.props) {
            if (prop.defaultValue != null) {
                expression(prop.defaultValue, add);
            }
        }
        for (source in template.sources) {
            expression(source.call, add);
        }
        nodes(template.nodes, add, components);
        return found;
    }

    static function nodes(list:Array<CheckedNode>, add:(Null<String>, String) -> Void,
            components:Null<Array<String>>):Void {
        for (node in list) {
            visit(node, add, components);
        }
    }

    static function visit(node:CheckedNode, add:(Null<String>, String) -> Void,
            components:Null<Array<String>>):Void {
        switch (node) {
            case Text(parts):
                textParts(parts, add);
            case Element(element):
                for (attribute in element.attributes) {
                    value(attribute.value, add);
                }
                if (element.swap != null) {
                    value(element.swap, add);
                }
                nodes(element.children, add, components);
            case Component(component):
                if (components != null && !components.contains(component.name)) {
                    components.push(component.name);
                }
                for (prop in component.props) {
                    value(prop.value, add);
                }
                for (attribute in component.forwarded) {
                    value(attribute.value, add);
                }
                for (slot in component.slots) {
                    nodes(slot.children, add, components);
                }
            case SlotOutlet(outlet):
                if (outlet.exposes != null) {
                    expression(outlet.exposes, add);
                }
                nodes(outlet.fallback, add, components);
            case Branches(branches):
                for (branch in branches) {
                    if (branch.condition != null) {
                        expression(branch.condition, add);
                    }
                    visit(branch.node, add, components);
                }
            case Repeat(repeat):
                expression(repeat.list, add);
                visit(repeat.body, add, components);
                if (repeat.empty != null) {
                    visit(repeat.empty, add, components);
                }
            case Group(children) | Head(children):
                nodes(children, add, components);
            case Island(island):
                if (island.props != null) {
                    expression(island.props, add);
                }
                nodes(island.fallback, add, components);
            case Doctype(_) | HeadOutlet | Asset(_, _) | Assets:
        }
    }

    static function textParts(parts:Array<CheckedPart>, add:(Null<String>, String) -> Void):Void {
        for (part in parts) {
            switch (part) {
                case Print(printed) | PrintHtml(printed):
                    expression(printed, add);
                case Literal(_):
            }
        }
    }

    static function value(attribute:AttributeValue, add:(Null<String>, String) -> Void):Void {
        switch (attribute) {
            case Static(parts):
                textParts(parts, add);
            case Bound(bound):
                expression(bound, add);
            case Classes(parts, bound):
                textParts(parts, add);
                if (bound != null) {
                    expression(bound, add);
                }
            case Present:
        }
    }

    static function literal(expression:TypedExpr):Null<String> {
        return switch (expression.kind) {
            case Constant(CString(text)): text;
            default: null;
        }
    }

    static function expression(checked:TypedExpr, add:(Null<String>, String) -> Void):Void {
        switch (checked.kind) {
            case HelperCall(helper, arguments):
                if (helper.name == "t" && arguments.length > 0) {
                    var key = literal(arguments[0].value);
                    if (key != null) {
                        add(null, key);
                    }
                } else if (helper.name == "translate" && arguments.length > 1) {
                    var namespace = literal(arguments[0].value);
                    var key = literal(arguments[1].value);
                    if (namespace != null && key != null) {
                        add(namespace, key);
                    }
                }
                for (argument in arguments) {
                    expression(argument.value, add);
                }
            case SourceCall(_, arguments):
                for (argument in arguments) {
                    expression(argument.value, add);
                }
            case FilterCall(target, _, arguments):
                expression(target, add);
                for (argument in arguments) {
                    expression(argument.value, add);
                }
            case FieldAccess(target, _, _):
                expression(target, add);
            case IndexAccess(target, key):
                expression(target, add);
                expression(key, add);
            case ListValue(items):
                for (item in items) {
                    expression(item, add);
                }
            case RecordValue(entries):
                for (entry in entries) {
                    expression(entry.value, add);
                }
            case UnaryOp(_, operand):
                expression(operand, add);
            case BinaryOp(_, left, right):
                expression(left, add);
                expression(right, add);
            case Choice(condition, consequent, alternative):
                expression(condition, add);
                expression(consequent, add);
                if (alternative != null) {
                    expression(alternative, add);
                }
            case Constant(_) | Name(_, _) | Root(_):
        }
    }
}
