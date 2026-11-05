package hx.press.themes;

import haxe.Json;
import hx.press.ContentCache;
import hx.press.model.ThemeDesign;
import hx.press.model.InstalledPackage;

typedef ThemeDesignRecord = {
    var id:String;
    var draft:String;
    var version:Int;
    var published_version:Int;
}

class ThemeDesignData {
    public static function status(id:String):Null<{version:Int, published_version:Int}> {
        return ContentCache.remember("extensions", "theme-design-status", [id], () -> {
            var model = ThemeDesign.query.select(["version", "published_version"])
                .where("id", id)
                .limit(1)
                .first();
            return model == null ? null : cast model.toObject();
        });
    }

    public static function snapshot(id:String):Dynamic {
        var model = InstalledPackage.query.select(["name", "enabled"])
            .where("id", id)
            .where("kind", "theme")
            .limit(1)
            .first();
        var record = editor(id);
        if (model == null || record == null) {
            return null;
        }
        return {
            id: id,
            name: model.name,
            enabled: model.enabled == 1,
            document: ThemeDesignSchema.parse(record.draft),
            version: record.version,
            publishedVersion: record.published_version
        };
    }

    public static function editor(id:String):Null<ThemeDesignRecord> {
        var model = ThemeDesign.query.select(["id", "draft", "version", "published_version"])
            .where("id", id)
            .limit(1)
            .first();
        return model == null ? null : cast model.toObject();
    }

    public static function published(id:String, preview:Bool):Dynamic {
        var record:Null<{published:String, draft:String}> = ContentCache.remember("extensions",
            "theme-design", [id, preview], () -> {
                var columns = preview ? ["published", "draft"] : ["published"];
                var model = ThemeDesign.query.select(columns).where("id", id).limit(1).first();
                return model == null ? null : cast model.toObject();
            });
        if (record == null) {
            return null;
        }
        var source = record.published;
        if (source == "" && preview) {
            source = record.draft;
        }
        if (source == "") {
            return null;
        }
        var document:Dynamic = Json.parse(source);
        return document.schema == 1 ? ThemeDesignSchema.parse(source) : document;
    }

    public static function identifiers(ids:Array<String>):Array<String> {
        if (ids.length == 0) {
            return [];
        }
        return ThemeDesign.query.select(["id"])
            .whereIn("id", cast ids)
            .limit(ids.length)
            .get()
            .map(model -> model.id);
    }
}
