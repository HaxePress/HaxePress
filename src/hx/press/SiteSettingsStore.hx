package hx.press;

import hx.press.i18n.SiteTexts;
import haxe.Json;
import hx.press.model.ContentItem;
import hx.press.model.Admin;
import hx.press.model.Setting;
import hx.press.model.Language;
import hx.press.i18n.Languages;
import hx.well.facades.Environment;
import hx.well.facades.Hash;
import hx.well.facades.DBStatic;
import hx.well.database.Connection;
import hx.well.facades.Storage;

class SiteSettingsStore {
    public static function timestamp():String
        return Date.now().toString();

    public static function initialize():Void {
        var settingsChanged = false;
        var contentChanged = false;
        var defaults = [
            "home_mode" => "collection",
            "home_type" => "entry",
            "home_page" => "0",
            "home_size" => "7",
            "home_template" => "Home",
            "site_name" => Environment.env("SITE_NAME", "HaxePress"),
            "site_logo" => "",
            "publisher_name" => "",
            "description" => "",
            "about_site" => ""
        ];
        for (key => value in defaults)
            if (!Setting.query.where("key", key).exists()) {
                Setting.query.insert(["key" => key, "value" => value]);
                settingsChanged = true;
            }
        if (!Language.query.select(["code"]).exists()) {
            var code = Languages.configuredDefault();
            Language.query.insert([
                "code" => code,
                "name" => Languages.suggestedName(code),
                "direction" => Languages.suggestedDirection(code),
                "position" => 0,
                "is_default" => 1,
                "enabled" => 1,
                "home_page_id" => 0,
                "updated_epoch" => Date.now().getTime() / 1000
            ]);
            ContentCache.changed("languages");
        }
        if (!Admin.query.select(["id"]).exists()) {
            var email = CategoryData.key(Environment.env("ADMIN_EMAIL", ""));
            var password = Environment.env("ADMIN_PASSWORD", "");
            if (email == "" || password.length < 12)
                throw "Set ADMIN_EMAIL and a password of at least 12 characters in .env before starting.";
            Admin.query.insert([
                "email" => email,
                "password" => Hash.make(password),
                "name" => Environment.env("ADMIN_NAME", "Administrator"),
                "created_at" => timestamp()
            ]);
        }
        if (!Setting.query.where("key", "seeded").exists()) {
            var seeds:Array<Dynamic> = Storage.disk("seeds").json("seed.json");
            DBStatic.transaction(() -> {
                for (item in (Environment.env("CMS_SEED_DEMO", "true") == "true" ? seeds : [])) {
                    var data:Map<String, Dynamic> = new Map();
                    for (key in [
                        "title",
                        "slug",
                        "excerpt",
                        "content",
                        "category",
                        "image",
                        "image_alt",
                        "status",
                        "featured",
                        "published_at"
                    ])
                        data.set(key, Reflect.field(item, key));
                    data.set("created_at", timestamp());
                    data.set("updated_at", timestamp());
                    ContentItem.query.insert(data);
                }
                Setting.query.insert(["key" => "seeded", "value" => "1"]);
            });
            contentChanged = true;
        }
        Connection.free();
        if (settingsChanged) {
            ContentCache.settingsChanged();
            var name = Setting.query.select(["value"]).where("key", "site_name").first();
            if (name != null) {
                SiteTexts.put("setting.site_name", "setting", name.value);
            }
        }
        if (contentChanged)
            ContentCache.contentChanged();
    }

    public static function settings():Map<String, String> {
        var fields = [
            "site_name",
            "site_logo",
            "publisher_name",
            "description",
            "about_site",
            "home_mode",
            "home_type",
            "home_page",
            "home_size",
            "home_template"
        ];
        return ContentCache.remember("settings", "public", fields, () -> {
            var settings:Map<String, String> = [];
            var storedSettings = Setting.query.select(["key", "value"])
                .whereIn("key", fields)
                .limit(fields.length)
                .get();

            for (setting in storedSettings) {
                settings.set(setting.key, setting.value);
            }

            return settings;
        });
    }
}
