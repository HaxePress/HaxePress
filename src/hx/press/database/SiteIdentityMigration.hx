package hx.press.database;

import hx.press.ContentCache;
import hx.press.model.Setting;
import hx.well.facades.DBStatic;

class SiteIdentityMigration {
    public static function up():Void {
        var names = ["author_name" => "publisher_name", "author_bio" => "about_site"];
        var legacy = Setting.query.select(["key", "value"])
            .whereIn("key", ["author_name", "author_bio"])
            .limit(2)
            .get();
        if (legacy.length == 0) {
            return;
        }
        DBStatic.transaction(() -> {
            for (setting in legacy) {
                var key = names.get(setting.key);
                if (Setting.query.find(key) == null) {
                    Setting.query.create(["key" => key, "value" => setting.value]);
                }
                setting.delete();
            }
        });
        ContentCache.settingsChanged();
    }
}
