package plugins;

import haxe.Exception;
import haxe.Resource;
import hx.press.i18n.TranslationCatalogue;
import hx.press.model.InstalledPackage;
import hx.press.model.PackageHook;
import hx.press.packages.BuiltInTheme;
#if jvm
import hx.press.model.PackageUpload;
import hx.press.packages.PackageManager;
import hx.well.internal.SecureToken;
#end

class BuiltInThemeChecks {
    static function check(value:Bool, message:String):Void {
        if (!value) {
            throw new Exception(message);
        }
    }

    static function rejects(action:Void->Void, message:String):Void {
        var rejected = false;
        try {
            action();
        } catch (_:Dynamic) {
            rejected = true;
        }
        check(rejected, message);
    }

    public static function run():Void {
        BuiltInTheme.ensure();
        var current = InstalledPackage.query.find(BuiltInTheme.ID);
        check(current != null && current.directory == "",
            "The default theme still needs package files");
        check(PackageHook.query.where("package_id", BuiltInTheme.ID)
            .where("event", "i18n.catalogues")
            .exists(),
            "The built-in theme did not register its embedded catalogue");
        var settings = current.settings;
        var updated = Std.string(current.updated_at);
        var enabled = current.enabled;
        BuiltInTheme.ensure();
        current = InstalledPackage.query.find(BuiltInTheme.ID);
        check(current.settings == settings, "Idempotent boot rewrote built-in settings");
        check(Std.string(current.updated_at) == updated,
            "Idempotent boot rewrote built-in timestamps");
        current.update(["enabled" => 0]);
        #if jvm
        rejects(() -> PackageManager.uninstall(BuiltInTheme.ID, 0, "Test"),
            "An inactive built-in theme was uninstalled");
        var token = SecureToken.generate(32);
        PackageUpload.query.create([
            "key" => token,
            "user_id" => 0,
            "kind" => "theme",
            "directory" => "staging/" + token,
            "manifest" => Resource.getString(BuiltInTheme.RESOURCE),
            "expires_epoch" => Date.now().getTime() + 60000
        ]);
        rejects(() -> PackageManager.install(token, "theme", 0, "Test", true),
            "A previously staged upload replaced the built-in theme");
        PackageUpload.query.where("key", token).delete();
        #end
        current = InstalledPackage.query.find(BuiltInTheme.ID);
        check(current.directory == "" && current.settings == settings && current.enabled == 0,
            "A rejected mutation changed the built-in theme");
        current.update(["enabled" => enabled]);
        var messages = TranslationCatalogue.parse(BuiltInTheme.translations("tr"));
        check(messages.get("Simple") == "Sade",
            "Built-in translations need external package files");
        Sys.println("PASS Native built-in theme: embedded registration/translations, idempotency and preserved settings");
    }
}
