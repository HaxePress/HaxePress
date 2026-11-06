package hx.press;

import hx.press.SiteSettingsStore;
import hx.press.model.ActivityLog;

class Activity {
    public static function record(action:String, entity:String, id:Int, label:String):Void {
        var admin = CmsAccess.current();
        append(admin == null ? 0 : admin.id, admin == null ? "System" : admin.name, action,
            entity, id, label);
    }

    public static function append(userId:Int, actor:String, action:String, entity:String, id:Int,
            label:String):Void {
        ActivityLog.query.insert([
            "user_id" => userId,
            "actor" => actor,
            "action" => action,
            "entity" => entity,
            "entity_id" => id,
            "label" => label.substr(0, 180),
            "created_at" => SiteSettingsStore.timestamp()
        ]);
    }
}
