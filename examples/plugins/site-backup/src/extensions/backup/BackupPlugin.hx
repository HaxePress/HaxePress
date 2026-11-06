package extensions.backup;

import hx.press.plugins.PluginEntrypoint;
import hx.press.plugins.PluginHost;
#if jvm
import haxe.Json;
import hx.press.access.Roles;
import hx.press.backup.BackupSchedules;
import hx.press.backup.BackupUploads;
import hx.press.backup.BackupUploads.BackupUploadPurpose;
import hx.press.backup.SiteBackup;
import hx.well.route.Route;
#end

class BackupPlugin implements PluginEntrypoint {
    public function new() {}

    public function onCreate(host:PluginHost, context:String):Void {
        #if jvm
        Roles.ensureCapability(SiteBackup.CAPABILITY, "Manage site backups", "Backups");
        host.admin(() -> {
            Route.path("/backups").group(() -> {
                Route.get("", SiteBackup.page).attribute("cms.navigation", {
                    group: "Administration",
                    groupPosition: 30,
                    label: "Backup / Restore",
                    icon: "database",
                    capability: SiteBackup.CAPABILITY,
                    position: 21,
                    exact: true
                });
                Route.post("", SiteBackup.export);
                Route.post("/verify", SiteBackup.verify);
                BackupUploads.register("/verify/uploads", BackupUploadPurpose.Verify);
                Route.get("/downloads/{token}", SiteBackup.download);
                Route.post("/schedules", BackupSchedules.save);
                Route.post("/schedules/{key}", BackupSchedules.save);
                Route.delete("/schedules/{key}", BackupSchedules.remove);
                // HTML forms cannot send DELETE; the backups page posts here.
                Route.post("/schedules/{key}/delete", BackupSchedules.remove);
                Route.get("/schedules/{key}/files", BackupSchedules.files);
                Route.get("/scheduled-downloads/{file}", BackupSchedules.download);
            });
        });
        #end
    }

    public function onDestroy():Void {}

    public function dispatch(event:String, context:String):String {
        #if jvm
        if (event == "schedule.run") {
            var input:Dynamic = Json.parse(context);
            BackupSchedules.run(input.data);
        }
        #end
        return "{}";
    }
}
