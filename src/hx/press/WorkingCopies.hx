package hx.press;

import hx.press.content.ContentLocks;
import hx.press.SiteSettingsStore;
import haxe.Exception;
import haxe.Json;
import hx.well.internal.SecureToken;
import hx.press.model.EditorDraft;
import hx.press.content.ContentTypes;
import hx.press.media.MediaLocks;

class WorkingCopies {
    static function validNewKey(value:String, userId:Int, kind:String):Bool {
        var prefix = "draft-" + userId + "-" + kind + "-";
        return ContentTypes.validKey(kind)
            && StringTools.startsWith(value, prefix)
            && ~/^[A-Za-z0-9_-]{32}$/.match(value.substr(prefix.length));
    }

    public static function key(userId:Int, kind:String, documentId:Int):String {
        return "draft-" + userId + "-" + kind + "-" + documentId;
    }

    public static function freshKey(userId:Int, kind:String):String {
        return "draft-" + userId + "-" + kind + "-" + SecureToken.generate(32);
    }

    public static function find(userId:Int, kind:String, documentId:Int,
            newKey:String = ""):Dynamic {
        var draftKey = documentId > 0 ? key(userId, kind, documentId) : newKey;
        if (draftKey == "") {
            return null;
        }
        var row = EditorDraft.query.select(["key", "payload", "base_version", "version", "updated_at"])
            .where("key", draftKey)
            .where("user_id", userId)
            .where("kind", kind)
            .where("expires_epoch", ">", Date.now().getTime())
            .limit(1)
            .first();
        return row == null ? null : {
            key: row.key,
            data: Json.parse(row.payload),
            baseVersion: row.base_version,
            version: row.version,
            updatedAt: Std.string(row.updated_at)
        };
    }

    public static function save(userId:Int, kind:String, documentId:Int, draftKey:String,
            version:Int, baseVersion:Int, payload:Dynamic):String {
        if (documentId > 0) {
            draftKey = key(userId, kind, documentId);
        } else if (!validNewKey(draftKey, userId, kind)) {
            throw new Exception("Open a new editor before saving this working copy.");
        }
        var encoded = Json.stringify(payload);
        if (encoded.length > 512000 || version < 1) {
            throw new Exception("This working copy exceeds the editor limits.");
        }
        var selectedKey = draftKey;
        ContentLocks.run("working-" + draftKey, () -> MediaLocks.run(() -> {
            var previous = EditorDraft.query.select(["key", "version", "document_id"])
                .where("key", selectedKey)
                .where("user_id", userId)
                .limit(1)
                .first();
            if (documentId == 0 && previous != null && previous.document_id > 0) {
                throw new Exception("This working copy has already been saved as content.");
            }
            if (previous != null && previous.version >= version) {
                return false;
            }
            var values:Map<String, Dynamic> = [
                "key" => selectedKey,
                "document_id" => documentId,
                "user_id" => userId,
                "kind" => kind,
                "title" => Std.string(payload.title ?? "Untitled").substr(0, 180),
                "payload" => encoded,
                "version" => version,
                "base_version" => baseVersion,
                "expires_epoch" => Date.now().getTime() + 604800000,
                "updated_at" => SiteSettingsStore.timestamp()
            ];
            if (previous == null) {
                EditorDraft.query.create(values);
            } else {
                previous.update(values);
            }
            return true;
        }));
        return draftKey;
    }

    public static function clear(userId:Int, documentId:Int, kind:String,
            draftKey:String = ""):Void {
        var query = EditorDraft.query.where("user_id", userId).where("kind", kind);
        if (documentId > 0) {
            query.where("document_id", documentId).where("key", key(userId, kind, documentId));
        } else {
            query.where("key", draftKey);
        }
        query.delete();
    }

    public static function consume(userId:Int, documentId:Int, kind:String, draftKey:String):Void {
        if (!validNewKey(draftKey, userId, kind)) {
            return;
        }
        EditorDraft.query.updateOrCreate(["key" => draftKey], [
            "document_id" => documentId,
            "user_id" => userId,
            "kind" => kind,
            "title" => "Saved content",
            "payload" => "{}",
            "version" => 2147483647,
            "base_version" => 1,
            "expires_epoch" => Date.now().getTime() + 3600000,
            "updated_at" => SiteSettingsStore.timestamp()
        ]);
    }

    public static function expire():Void {
        var expired = EditorDraft.query.select(["key"])
            .where("expires_epoch", "<=", Date.now().getTime())
            .orderBy("key")
            .limit(50)
            .get();
        if (expired.length > 0) {
            EditorDraft.query.select(["key"])
                .whereIn("key", [for (draft in expired) draft.key])
                .delete();
        }
    }
}
