package hx.press.packages;

import hx.press.packages.PackageManifest.ManifestData;
import hx.press.packages.PackageManifest.PackageField;
import haxe.Exception;
import haxe.Json;
import hx.well.facades.Crypt;

class PackageSettings {
    public static function stored(source:String):Map<String, String> {
        var parsed:Dynamic = Json.parse(source);
        var values:Map<String, String> = [];
        for (key in Reflect.fields(parsed)) {
            var value = Reflect.field(parsed, key);
            if (Std.isOfType(value, String)) {
                values.set(key, value);
            }
        }
        return values;
    }

    public static function defaults(manifest:ManifestData):Map<String, String> {
        var values:Map<String, String> = [];
        for (field in manifest.fields) {
            var value = field.defaultValue;
            if (value == "" && field.kind == "boolean") {
                value = "false";
            }
            if (value == "" && field.kind == "color" && field.required) {
                value = "#31543f";
            }
            if (value == "" && field.kind == "select") {
                value = field.options[0].value;
            }
            if (value == "" && field.kind == "number") {
                value = Std.string(Math.max(field.minimum, Math.min(field.maximum, 0)));
            }
            values.set(field.key, value);
        }
        return values;
    }

    public static function validate(field:PackageField, value:String):String {
        value = StringTools.trim(value);
        if (field.required && value == "") {
            throw new Exception(field.label + " is required.");
        }
        var limit = field.kind == "textarea" || field.kind == "secret" ? 2000 : 240;
        if (value.length > limit) {
            throw new Exception(field.label + " is too long.");
        }
        if (value == "" && !field.required) {
            return value;
        }
        switch (field.kind) {
            case "boolean":
                if (value != "true" && value != "false") {
                    throw new Exception("Choose a valid value for " + field.label + ".");
                }
            case "color":
                if (!~/^#[0-9A-Fa-f]{6}$/.match(value)) {
                    throw new Exception("Choose a six-digit color for " + field.label + ".");
                }
            case "number":
                var number = Std.parseFloat(value);
                if (!~/^-?[0-9]+(\.[0-9]+)?$/.match(value)
                    || !Math.isFinite(number)
                    || number < field.minimum
                    || number > field.maximum) {
                    throw new Exception("Enter a number in the allowed range for "
                        + field.label
                        + ".");
                }
            case "select":
                var choices = field.options.map(option -> option.value);
                if (!choices.contains(value)) {
                    throw new Exception("Choose a valid option for " + field.label + ".");
                }
            default:
        }
        return value;
    }

    public static function values(manifest:ManifestData, source:String,
            includeSecrets:Bool):Map<String, String> {
        var input = stored(source);
        var result = defaults(manifest);
        for (field in manifest.fields) {
            if (field.kind == "secret") {
                if (!includeSecrets) {
                    result.remove(field.key);
                    continue;
                }
                var encrypted = input.get(field.key);
                result.set(field.key, encrypted == null || encrypted == "" ? "" : Crypt.decryptString(encrypted));
            } else if (input.exists(field.key)) {
                result.set(field.key, input.get(field.key));
            }
        }
        return result;
    }

    public static function prepare(manifest:ManifestData, current:String,
            input:Map<String, String>, clear:Array<String>):Map<String, String> {
        var previous = stored(current);
        var result = defaults(manifest);
        for (field in manifest.fields) {
            var value = input.get(field.key) ?? "";
            if (field.kind == "secret") {
                if (value == "" && !clear.contains(field.key)) {
                    result.set(field.key, previous.get(field.key) ?? "");
                    continue;
                }
                value = validate(field, value);
                result.set(field.key, value == "" ? "" : Crypt.encryptString(value));
            } else {
                result.set(field.key, validate(field, value));
            }
        }
        return result;
    }

    public static function ready(manifest:ManifestData, source:String):Void {
        var configured = values(manifest, source, true);
        for (field in manifest.fields) {
            validate(field, configured.get(field.key) ?? "");
        }
    }
}
