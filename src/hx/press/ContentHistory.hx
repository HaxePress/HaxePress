package hx.press;

import hx.press.SiteSettingsStore;
import hx.press.TagData.TagRecord;
import haxe.Json;
import hx.press.model.ContentRevision;
import hx.press.model.ContentItem;
import hx.press.content.ContentFields;
import hx.press.content.ContentTypes;

class ContentHistory {
    public static function remember(document:ContentItem, tags:Array<TagRecord>, userId:Int):Void {
        var type = ContentTypes.find(document.content_type, false);
        if (!ContentTypes.supports(type, "revisions")) {
            return;
        }
        if (ContentRevision.query.where("document_id", document.id)
            .where("version", document.version)
            .exists()) {
            return;
        }
        var snapshot:Dynamic = document.toObject();
        snapshot.tags = tags;
        snapshot.fields = ContentFields.values(document.id, type, false, false);
        ContentRevision.query.create([
            "document_id" => document.id,
            "version" => document.version,
            "title" => document.title,
            "snapshot" => Json.stringify(snapshot),
            "author_id" => userId,
            "created_at" => SiteSettingsStore.timestamp()
        ]);
        ContentRevision.query.where("document_id", document.id)
            .where("version", "<", document.version - 49)
            .delete();
    }
}
