package hx.press;

import hx.press.SiteSettingsStore;
import hx.press.ai.AdminMcpAccess;
import hx.press.model.ActivityLog;
import hx.press.themes.ThemeAiAccess;
import hx.well.http.RequestStatic;

class Activity {
    /** The source recorded for changes an MCP client makes. **/
    public static inline var MCP = "mcp";

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
            "created_at" => SiteSettingsStore.timestamp(),
            "source" => source()
        ]);
    }

    /**
        `mcp` when the current request comes from an MCP client: a remote or
        browser admin connection, or a theme designer connection.
    **/
    static function source():String {
        var request = RequestStatic.request();
        if (request == null) {
            return "";
        }
        var admin = request.getAttribute(AdminMcpAccess.INTERNAL, false) == true;
        var designer = request.getAttribute(ThemeAiAccess.ACTOR, null) != null;
        return admin || designer ? MCP : "";
    }
}
