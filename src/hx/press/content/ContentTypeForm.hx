package hx.press.content;

import haxe.ds.StringMap;
import hx.press.content.ContentTypeDefinition;
import hx.press.content.ContentTypes;

/**
    The collection editor as a server-rendered form. `read` turns the
    submitted fields into the definition input `ContentTypes.save` accepts,
    `apply` runs the custom field list actions (add, move, remove), `values`
    turns a definition input back into form values for a redirect, and
    `view` prepares what the editor template shows.
**/
class ContentTypeForm {
    static inline var MAX_FIELDS = 32;
    static final labelKeys = ["create", "edit", "save", "title", "description"];
    static final defaultFeatures = ["body", "excerpt", "image", "seo", "revisions", "schedule"];
    static final unlistedKinds = ["textarea", "image"];
    static final featureLabels = [
        "body" => "Content editor",
        "excerpt" => "Excerpt",
        "categories" => "Categories",
        "tags" => "Tags",
        "image" => "Cover image",
        "seo" => "Search appearance",
        "featured" => "Featured content",
        "reading_time" => "Reading time",
        "revisions" => "Revision history",
        "schedule" => "Scheduled publication"
    ];
    static final limits = [
        {
            key: "minimumTitleLength",
            label: "Minimum title length",
            minimum: 1,
            maximum: 180
        },
        {
            key: "minimumContentLength",
            label: "Minimum body length",
            minimum: 0,
            maximum: 100000
        },
        {
            key: "minimumExcerptLength",
            label: "Minimum excerpt length",
            minimum: 0,
            maximum: 500
        }
    ];

    /** Whether submitted values come from this form rather than a JSON `definition`. **/
    public static function submitted(value:String->Null<String>):Bool {
        return value("field_count") != null;
    }

    /** Reads a value from a request input map or a flashed record of form values. **/
    public static function reader(source:Dynamic):String->Null<String> {
        return key -> {
            var value:Dynamic = Std.isOfType(source,
                StringMap) ? (source : StringMap<Dynamic>).get(key) : Reflect.field(source, key);
            return Std.isOfType(value, String) ? value : null;
        };
    }

    /** The editor's starting values: a stored definition, or the defaults of a new collection. **/
    public static function initial(type:Null<ContentTypeDefinition>):Dynamic {
        if (type == null) {
            return {
                key: "",
                name: "",
                singular: "",
                description: "",
                publicPath: "",
                icon: "file",
                position: 10,
                publicVisible: true,
                hasArchive: true,
                enabled: true,
                dedicatedAccess: false,
                template: "ContentDetail",
                archiveTemplate: "ContentIndex",
                minimumTitleLength: 1,
                minimumContentLength: 0,
                minimumExcerptLength: 0,
                features: defaultFeatures.copy(),
                fields: [],
                labels: emptyLabels()
            };
        }
        var labels:Dynamic = emptyLabels();
        for (key in labelKeys) {
            var label:Dynamic = type.labels == null ? null : Reflect.field(type.labels, key);
            Reflect.setField(labels, key, label == null ? "" : Std.string(label));
        }
        var fields:Array<Dynamic> = [
            for (field in type.fields)
                {
                    key: field.key,
                    label: field.label,
                    kind: field.kind,
                    help: field.help,
                    required: field.required,
                    publicVisible: field.publicVisible,
                    filterable: field.filterable,
                    inList: field.inList,
                    options: field.options.copy()
                }
        ];
        return {
            key: type.key,
            name: type.name,
            singular: type.singular,
            description: type.description,
            publicPath: type.publicBase.substr(1),
            icon: type.icon == "" ? "file" : type.icon,
            position: type.position,
            publicVisible: type.publicVisible,
            hasArchive: type.hasArchive,
            enabled: type.enabled,
            dedicatedAccess: type.capability != "" && type.capability != "content",
            template: type.template == "" ? "ContentDetail" : type.template,
            archiveTemplate: type.archiveTemplate == "" ? "ContentIndex" : type.archiveTemplate,
            minimumTitleLength: type.minimumTitleLength,
            minimumContentLength: type.minimumContentLength,
            minimumExcerptLength: type.minimumExcerptLength,
            features: type.features.copy(),
            fields: fields,
            labels: labels
        };
    }

    /**
        The definition input of a submitted editor form. Built-in collections
        stay enabled, since their checkbox is disabled and not submitted.
    **/
    public static function read(value:String->Null<String>, system:Bool):Dynamic {
        var text = (key:String) -> value(key) ?? "";
        var flag = (key:String) -> value(key) == "1";
        var features = [
            for (feature in ContentTypes.supportedFeatures)
                if (flag('feature_${feature}')) feature
        ];
        var labels:Dynamic = {};
        for (key in labelKeys) {
            Reflect.setField(labels, key, text('label_${key}'));
        }
        var count = Std.parseInt(text("field_count")) ?? 0;
        if (count < 0) {
            count = 0;
        } else if (count > MAX_FIELDS + 1) {
            count = MAX_FIELDS + 1;
        }
        var fields:Array<Dynamic> = [for (index in 0...count) readField(value, index)];
        var input:Dynamic = {
            key: text("key"),
            name: text("name"),
            singular: text("singular"),
            description: text("description"),
            publicPath: text("publicPath"),
            icon: text("icon"),
            position: Std.parseInt(text("position")) ?? 10,
            publicVisible: flag("publicVisible"),
            hasArchive: flag("hasArchive"),
            enabled: system || flag("enabled"),
            dedicatedAccess: flag("dedicatedAccess"),
            template: text("template"),
            archiveTemplate: text("archiveTemplate"),
            features: features,
            fields: fields,
            labels: labels
        };
        for (limit in limits) {
            Reflect.setField(input, limit.key, number(text(limit.key)));
        }
        return input;
    }

    static function readField(value:String->Null<String>, index:Int):Dynamic {
        var text = (name:String) -> value('field_${index}_${name}') ?? "";
        var flag = (name:String) -> value('field_${index}_${name}') == "1";
        var kind = text("kind") == "" ? "text" : text("kind");
        var scalar = !unlistedKinds.contains(kind);
        var publicVisible = flag("publicVisible");
        var optionsText = text("options");
        return {
            key: text("key"),
            label: text("label"),
            kind: kind,
            help: text("help"),
            required: flag("required"),
            publicVisible: publicVisible,
            filterable: scalar && publicVisible && flag("filterable"),
            inList: scalar && flag("inList"),
            options: parseOptions(optionsText),
            optionsText: optionsText
        };
    }

    /** One choice per line: `stable value | display label`, the label defaulting to the value. **/
    static function parseOptions(source:String):Array<{value:String, label:String}> {
        var options:Array<{value:String, label:String}> = [];
        for (line in ~/\r?\n/g.split(source)) {
            if (StringTools.trim(line) == "") {
                continue;
            }
            var parts = line.split("|");
            var value = StringTools.trim(parts.shift());
            var label = StringTools.trim(parts.join("|"));
            options.push({value: value, label: label == "" ? value : label});
        }
        return options;
    }

    /** A whole number as an `Int`; anything else stays text, so saving reports it. **/
    static function number(source:String):Dynamic {
        var trimmed = StringTools.trim(source);
        if (trimmed == "") {
            return 0;
        }
        return ~/^-?[0-9]{1,9}$/.match(trimmed) ? Std.parseInt(trimmed) : trimmed;
    }

    /**
        Applies a custom field list action: `add-field`, `up-N`, `down-N` or
        `remove-N`. Returns the index of the field to show afterwards, or -1
        for the field list itself.
    **/
    public static function apply(input:Dynamic, action:String):Int {
        var fields:Array<Dynamic> = input.fields;
        if (action == "add-field") {
            if (fields.length >= MAX_FIELDS) {
                return -1;
            }
            fields.push({
                key: "",
                label: "",
                kind: "text",
                help: "",
                required: false,
                publicVisible: true,
                filterable: false,
                inList: false,
                options: [],
                optionsText: ""
            });
            return fields.length - 1;
        }
        var pattern = ~/^(up|down|remove)-([0-9]{1,2})$/;
        if (!pattern.match(action)) {
            return -1;
        }
        var index = Std.parseInt(pattern.matched(2));
        if (index >= fields.length) {
            return -1;
        }
        var target = switch (pattern.matched(1)) {
            case "up": index - 1;
            case "down": index + 1;
            default: -1;
        };
        if (pattern.matched(1) == "remove") {
            fields.splice(index, 1);
            return index > 0 ? index - 1 : -1;
        }
        if (target < 0 || target >= fields.length) {
            return index;
        }
        var moved = fields[index];
        fields[index] = fields[target];
        fields[target] = moved;
        return target;
    }

    /** The form values of a definition input, flashed to show it again after a redirect. **/
    public static function values(input:Dynamic):Map<String, String> {
        var result:Map<String, String> = [];
        for (key in [
            "key",
            "name",
            "singular",
            "description",
            "publicPath",
            "icon",
            "template",
            "archiveTemplate"
        ]) {
            result.set(key, Std.string(Reflect.field(input, key) ?? ""));
        }
        result.set("position", Std.string(input.position));
        for (key in ["publicVisible", "hasArchive", "enabled", "dedicatedAccess"]) {
            if (Reflect.field(input, key) == true) {
                result.set(key, "1");
            }
        }
        for (limit in limits) {
            result.set(limit.key, Std.string(Reflect.field(input, limit.key)));
        }
        var features:Array<String> = input.features;
        for (feature in features) {
            result.set('feature_${feature}', "1");
        }
        for (key in labelKeys) {
            result.set('label_${key}', Std.string(Reflect.field(input.labels, key) ?? ""));
        }
        var fields:Array<Dynamic> = input.fields;
        result.set("field_count", Std.string(fields.length));
        for (index in 0...fields.length) {
            var field = fields[index];
            var prefix = 'field_${index}_';
            result.set('${prefix}key', field.key);
            result.set('${prefix}label', field.label);
            result.set('${prefix}kind', field.kind);
            result.set('${prefix}help', field.help);
            result.set('${prefix}options', optionsText(field));
            for (flag in ["required", "publicVisible", "filterable", "inList"]) {
                if (Reflect.field(field, flag) == true) {
                    result.set('${prefix}${flag}', "1");
                }
            }
        }
        return result;
    }

    static function optionsText(field:Dynamic):String {
        var typed:Null<String> = field.optionsText;
        if (typed != null) {
            return typed;
        }
        var options:Null<Array<Dynamic>> = field.options;
        if (options == null) {
            return "";
        }
        return [for (option in options) '${option.value} | ${option.label}'].join("\n");
    }

    /** The field type choices, labelled by their translation keys. **/
    public static function kindOptions():Array<Dynamic> {
        return [
            for (kind in ContentTypes.fieldKinds)
                {value: kind, label: 'field.kind.${kind}', checked: false}
        ];
    }

    /** What the editor template shows for a definition input. **/
    public static function view(input:Dynamic, type:Null<ContentTypeDefinition>,
            creating:Bool):Dynamic {
        var selected:Array<String> = input.features;
        var features = [
            for (feature in ContentTypes.supportedFeatures)
                {
                    value: feature,
                    label: featureLabels.get(feature) ?? feature,
                    checked: selected.contains(feature)
                }
        ];
        var definitions:Array<Dynamic> = input.fields;
        var fields = [
            for (field in definitions)
                {
                    key: field.key,
                    label: field.label,
                    kind: field.kind,
                    help: field.help,
                    options: optionsText(field),
                    required: field.required == true,
                    publicVisible: field.publicVisible == true,
                    filterable: field.filterable == true,
                    inList: field.inList == true,
                    scalar: !unlistedKinds.contains(field.kind),
                    canFilter: field.publicVisible == true && !unlistedKinds.contains(field.kind)
                }
        ];
        var labels = [
            for (key in labelKeys)
                {
                    key: key,
                    label: 'type.label.${key}',
                    value: Std.string(Reflect.field(input.labels, key) ?? "")
                }
        ];
        var limitInputs = [
            for (limit in limits)
                {
                    key: limit.key,
                    label: limit.label,
                    minimum: limit.minimum,
                    maximum: limit.maximum,
                    value: Std.string(Reflect.field(input, limit.key))
                }
        ];
        var key = type == null ? "" : type.key;
        return {
            key: input.key,
            name: input.name,
            singular: input.singular,
            description: input.description,
            publicPath: input.publicPath,
            icon: input.icon,
            position: Std.string(input.position),
            publicVisible: input.publicVisible == true,
            hasArchive: input.hasArchive == true,
            enabled: input.enabled == true,
            dedicatedAccess: input.dedicatedAccess == true,
            template: input.template,
            archiveTemplate: input.archiveTemplate,
            features: features,
            fields: fields,
            fieldCount: fields.length,
            canAddField: fields.length < MAX_FIELDS,
            labels: labels,
            limits: limitInputs,
            savePath: creating ? "/admin/content-types/create" : '/admin/content-types/${key}/save',
            deletePath: creating ? "" : '/admin/content-types/${key}/delete',
            heading: type == null ? "" : type.name,
            owner: type == null ? "" : type.owner,
            system: type != null && type.system,
            removable: !creating && type != null && !type.system && type.owner == ""};
    }

    static function emptyLabels():Dynamic {
        var labels:Dynamic = {};
        for (key in labelKeys) {
            Reflect.setField(labels, key, "");
        }
        return labels;
    }
}
