package hx.press.view;

import hx.press.i18n.I18n;
import hx.press.i18n.TranslationCatalogue;
import hx.press.packages.PackageManifest.PackageField;
import hx.press.view.types.admin.SystemViews.ExtensionSettingFieldView;
import hx.press.view.types.admin.SystemViews.ExtensionSettingOptionView;

/**
    Prepares a package's setting fields for `PackageSettingField`: labels,
    help and option names translated with the package's catalogue first,
    and the attributes each control needs.
**/
class PackageFieldViews {
    public static inline final DEFAULT_COLOR = "#2457a6";

    public static function prepare(packageId:String, fields:Array<PackageField>,
            values:Map<String, String>,
            ?secrets:Map<String, Bool>):Array<ExtensionSettingFieldView> {
        var locale = I18n.locale();
        var own = I18n.installedMessages(packageId, locale);
        var core = I18n.coreMessages(locale);
        var translate = (key:String) -> {
            var message:Dynamic = own == null ? null : own.get(key);
            return TranslationCatalogue.format(message ?? core.get(key), key, null);
        };
        var prepared:Array<ExtensionSettingFieldView> = [];
        for (field in fields) {
            var value = values.get(field.key) ?? "";
            var secretSaved = secrets != null && secrets.get(field.key) == true;
            var options:Array<ExtensionSettingOptionView> = [
                for (option in field.options)
                    {
                        value: option.value,
                        label: translate(option.label),
                        selected: option.value == value
                    }
            ];
            var number = field.kind == "number";
            prepared.push({
                key: field.key,
                kind: field.kind,
                label: translate(field.label),
                help: field.help == "" ? "" : translate(field.help),
                required: field.required,
                value: value,
                inputType: inputType(field.kind),
                maxLength: field.kind == "secret" ? 2000 : 240,
                minimum: number ? numberText(field.minimum) : "",
                maximum: number ? numberText(field.maximum) : "",
                checked: value == "true",
                colorValue: colorValue(value, field.defaultValue),
                colorEnabled: field.required || value != "",
                secretSaved: secretSaved,
                options: options
            });
        }
        return prepared;
    }

    /** The color picker's value: the setting, else its default, as the toggle restores it. **/
    static function colorValue(value:String, defaultValue:String):String {
        var hexColor = ~/^#[0-9a-f]{6}$/i;
        if (hexColor.match(value)) {
            return value;
        }
        return hexColor.match(defaultValue) ? defaultValue : DEFAULT_COLOR;
    }

    static function inputType(kind:String):String {
        return switch kind {
            case "secret": "password";
            case "number": "number";
            default: "text";
        }
    }

    static function numberText(value:Float):String {
        if (Math.isNaN(value) || !Math.isFinite(value)) {
            return "";
        }
        return value == Math.ffloor(value) ? Std.string(Std.int(value)) : Std.string(value);
    }
}
