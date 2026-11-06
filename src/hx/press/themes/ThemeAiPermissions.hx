package hx.press.themes;

import haxe.crypto.Md5;
import hx.press.ContentCache;
import hx.press.model.ThemeAiPermission;

typedef AiPermissions = {
    var read:Bool;
    var edit:Bool;
    var media:Bool;
}

private typedef PermissionRecord = {
    var allow_read:Int;
    var allow_edit:Int;
    var allow_media:Int;
}

class ThemeAiPermissions {
    public static function forAdmin(themeId:String, adminId:Int, canUseMedia:Bool):AiPermissions {
        var record:Null<PermissionRecord> = ContentCache.remember("theme-ai-policy", "actor",
            [themeId, adminId], () -> {
                var model = ThemeAiPermission.query.select(["allow_read", "allow_edit", "allow_media"])
                    .where("theme_id", themeId)
                    .where("admin_id", adminId)
                    .limit(1)
                    .first();
                return model == null ? null : cast model.toObject();
            });
        var read = record == null || record.allow_read == 1;
        return {
            read: read,
            edit: read && (record == null || record.allow_edit == 1),
            media: read && canUseMedia && (record == null || record.allow_media == 1)
        };
    }

    public static function save(themeId:String, adminId:Int, permissions:AiPermissions):Void {
        ThemeAiPermission.query.upsert([
            "id" => Md5.encode('${themeId}:${adminId}'),
            "theme_id" => themeId,
            "admin_id" => adminId,
            "allow_read" => permissions.read ? 1 : 0,
            "allow_edit" => permissions.read && permissions.edit ? 1 : 0,
            "allow_media" => permissions.read && permissions.media ? 1 : 0
        ], ["theme_id", "admin_id"],
            ["allow_read", "allow_edit", "allow_media"]);
        ContentCache.changed("theme-ai-policy");
        ThemeCollaboration.permissionsChanged(themeId, adminId);
    }
}
