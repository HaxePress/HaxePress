package extensions.backup;

import hx.press.plugins.PluginEntrypoint;
import hx.press.plugins.PluginHost;
#if jvm
import haxe.Json;
import extensions.backup.BackupUploads.BackupUploadPurpose;
import hx.press.access.Roles;
import hx.press.http.BodyLimits;
import hx.press.install.Installation;
import hx.press.plugins.PluginDatabase;
import hx.press.plugins.PluginMigration;
import hx.well.facades.Schema;
import hx.well.route.Route;
#end

/**
    Site backups: prepare, verify, schedule and download backups in the
    administration, and restore one while installing a new site. Everything
    runs through the plugin API: its pages are templates in `views/`, its
    schedules are host tasks, and the installer starts it for the restore
    step because it subscribes to the `installation` hook.
**/
class BackupPlugin implements PluginEntrypoint {
    public static inline var NAMESPACE = "plugin-site-backup";
    public static var host:PluginHost;
    public static var identity:String = "";

    public function new() {}

    public function onCreate(host:PluginHost, context:String):Void {
        #if jvm
        var input:Dynamic = Json.parse(context);
        BackupPlugin.host = host;
        BackupPlugin.identity = input.packageInfo.pluginId;
        if (input.phase == "installation") {
            Installation.routes(() -> {
                Route.post("/restore", SiteBackup.restore)
                    .attribute(BodyLimits.ATTRIBUTE, BackupUploads.CONTROL_BYTES);
                BackupUploads.register("/restore/uploads", BackupUploadPurpose.Restore);
            });
            return;
        }
        migrate();
        Roles.ensureCapability(SiteBackup.CAPABILITY, "Manage site backups", "Backups");
        host.schedule(identity, BackupSchedules.CLEANUP, 60);
        host.admin(() -> {
            Route.path("/backups").group(() -> {
                // Listed under Extensions, and opened by the plugin's Settings button too.
                Route.get("", SiteBackup.page).attribute("cms.navigation", {
                    label: "Backup / Restore",
                    namespace: NAMESPACE,
                    icon: "database",
                    capability: SiteBackup.CAPABILITY,
                    exact: true
                }).attribute("cms.settings", {
                    capability: SiteBackup.CAPABILITY
                });
                Route.post("", SiteBackup.export);
                Route.post("/verify", SiteBackup.verify)
                    .attribute(BodyLimits.ATTRIBUTE, BackupUploads.CONTROL_BYTES);
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
        var input:Dynamic = Json.parse(context);
        if (event == "schedule.run") {
            if (input.data.key == BackupSchedules.CLEANUP) {
                SiteBackup.cleanup();
            } else {
                BackupSchedules.run(input.data);
            }
        }
        if (event == "installation.panel") {
            return Json.stringify(restoreStep(input.data));
        }
        #end
        return "{}";
    }

    #if jvm
    /** The restore step of the installation page: on the first step for SQLite, and after verifying a database. **/
    static function restoreStep(step:Dynamic):Dynamic {
        var offered = (step.step == 0 && step.driver == "sqlite") || step.step == 1;
        if (!offered) {
            return {};
        }
        var verified = step.verified == true;
        return {
            view: "InstallRestore",
            props: {
                restore: {
                    limit: BackupFormat.maxBytes(),
                    target: verified ? 'Restore into ${step.target}.' : "Restore into a new SQLite database.",
                    useVerifiedDatabase: verified
                }
            }
        };
    }

    /** Keeps the schedules' saved files in the table they used before the plugin owned it. **/
    static function migrate():Void {
        new PluginDatabase("site-backup").migrate([
            new PluginMigration("001_scheduled_backup_files", () -> {
                if (!Schema.hasTable("scheduled_backup_files")) {
                    Schema.create("scheduled_backup_files", table -> {
                        table.string("id", 32).primary();
                        table.string("schedule_id", 104);
                        table.double("created_epoch");
                        table.string("cms_version", 64);
                        table.integer("encrypted");
                        table.integer("size");
                        table.string("md5", 32);
                        table.index(["schedule_id", "created_epoch", "id"]);
                    });
                }
            })
        ]);
    }
    #end
}
