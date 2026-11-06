package hx.press.themes;

import haxe.Json;
#if (target.threaded)
import sys.thread.Mutex;
#else
import hx.well.thread.FakeMutex as Mutex;
#end
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
    static inline var MAX_PARSED_DOCUMENTS = 64;
    static final parsedDocuments:Map<String, {source:String, document:Dynamic}> = [];
    static final parsedDocumentsLock = new Mutex();

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

    /** A builder theme's saved draft, read without caching, for previews of work in progress. **/
    public static function draft(id:String):Dynamic {
        var record = editor(id);
        if (record == null || record.draft == "") {
            return null;
        }
        return parsedDocument('${id}:draft', record.draft);
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
        return parsedDocument('${id}:${preview}', source);
    }

    /**
        Parsed documents are shared read-only between requests. A document is
        parsed again only when its stored JSON differs from the cached source.
    **/
    static function parsedDocument(key:String, source:String):Dynamic {
        parsedDocumentsLock.acquire();
        var cached = parsedDocuments.get(key);
        parsedDocumentsLock.release();
        if (cached != null && cached.source == source) {
            return cached.document;
        }
        var parsed:Dynamic = Json.parse(source);
        var document:Dynamic = parsed.schema == 1 ? ThemeDesignSchema.parse(source) : parsed;
        parsedDocumentsLock.acquire();
        if (!parsedDocuments.exists(key) && Lambda.count(parsedDocuments) >= MAX_PARSED_DOCUMENTS) {
            parsedDocuments.clear();
        }
        parsedDocuments.set(key, {source: source, document: document});
        parsedDocumentsLock.release();
        return document;
    }

    /**
        The designed themes among `ids`, each with whether its saved design
        has changes that are not published yet.
    **/
    public static function publishStates(ids:Array<String>):Map<String, Bool> {
        var states:Map<String, Bool> = [];
        if (ids.length == 0) {
            return states;
        }
        var designs = ThemeDesign.query.select(["id", "version", "published_version"])
            .whereIn("id", cast ids)
            .limit(ids.length)
            .get();
        for (design in designs) {
            states.set(design.id, design.version != design.published_version);
        }
        return states;
    }
}
