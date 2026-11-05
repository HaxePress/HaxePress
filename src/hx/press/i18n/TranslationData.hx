package hx.press.i18n;

import hx.press.ContentCache;
import hx.press.model.InstalledPackage;

typedef TranslationPackageRecord = {
    var id:String;
    var directory:String;
    var manifest:String;
}

/** Only catalogue metadata is needed; package settings never enter these projections. */
class TranslationData {
    static inline var ACTIVE_LIMIT = 33;

    public static function one(id:String):Null<TranslationPackageRecord> {
        return ContentCache.remember("extensions", "translation-package", [id], () -> {
            var row = InstalledPackage.query.select(["id", "directory", "manifest"])
                .where("id", id)
                .where("enabled", 1)
                .limit(1)
                .first();
            return row == null ? null : cast row.toObject();
        });
    }

    public static function byIds(ids:Array<String>):Array<TranslationPackageRecord> {
        if (ids.length == 0) {
            return [];
        }
        var identifiers = ids.slice(0, 12);
        identifiers.sort(Reflect.compare);
        return ContentCache.remember("extensions", "translation-packages", identifiers, () -> {
            var rows = InstalledPackage.query.select(["id", "directory", "manifest"])
                .whereIn("id", identifiers)
                .orderBy("id")
                .limit(identifiers.length)
                .get();
            return [for (row in rows) (cast row.toObject() : TranslationPackageRecord)];
        });
    }

    public static function active():Array<TranslationPackageRecord> {
        return ContentCache.remember("extensions", "active-translation-packages", [ACTIVE_LIMIT],
            () -> {
                var rows = InstalledPackage.query.select([
                    "cms_packages.id AS id",
                    "cms_packages.directory AS directory",
                    "cms_packages.manifest AS manifest"
                ])
                    .innerJoin("package_hooks", "cms_packages.id", "=", "package_hooks.package_id")
                    .where("cms_packages.enabled", 1)
                    .where("package_hooks.event", "i18n.catalogues")
                    .orderBy("cms_packages.id")
                    .limit(ACTIVE_LIMIT)
                    .get();
                return [for (row in rows) (cast row.toObject() : TranslationPackageRecord)];
            });
    }
}
