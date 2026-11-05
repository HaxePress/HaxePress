package hx.press.database;

import hx.press.CategoryData;
import hx.press.ContentCache;
import hx.press.SiteSettingsStore;
import hx.well.database.Connection;
import hx.well.facades.DBStatic;
import hx.press.model.Category;
import hx.press.model.ContentItem;
import hx.press.model.Setting;
import hx.well.facades.Storage;

class ManagedCategories {
    public static function run():Void {
        if (Setting.query.find("managed_categories_v1") != null) {
            Connection.free();
            return;
        }
        var seeds:Array<Dynamic> = Storage.disk("seeds").json("seed.json");
        var names = [for (item in seeds) Std.string(item.category)];
        DBStatic.transaction(() -> {
            importNames(names);
            var after = "";
            while (true) {
                var rows = ContentItem.query.select(["category"])
                    .distinct()
                    .where("category", ">", after)
                    .orderBy("category")
                    .limit(100)
                    .get();
                if (rows.length == 0)
                    break;
                var batch = [for (row in rows) Std.string(row.category)];
                importNames(batch);
                after = batch[batch.length - 1];
            }
            Setting.query.create(["key" => "managed_categories_v1", "value" => "1"]);
        });
        Connection.free();
        ContentCache.categoriesChanged();
        ContentCache.contentChanged();
    }

    static function importNames(names:Array<String>):Void {
        for (name in names) {
            var key = CategoryData.key(name);
            var category = Category.query.where("name_key", key).limit(1).first();
            if (category == null) {
                Category.query.create([
                    "name" => name,
                    "name_key" => key,
                    "created_at" => SiteSettingsStore.timestamp(),
                    "updated_at" => SiteSettingsStore.timestamp()
                ]);
            } else if (category.name != name) {
                ContentItem.query.where("category", name).update(["category" => category.name]);
            }
        }
    }
}
