package plugins;

import haxe.Exception;
import haxe.Json;
import hx.press.ContentCache;
import hx.press.CmsVersion;
import hx.press.SiteSettingsStore;
import hx.press.access.Roles;
import hx.press.content.ContentFields;
import hx.press.content.ContentTypes;
import hx.press.model.Capability;
import hx.press.model.ContentItem;
import hx.press.model.ContentType;
import hx.press.model.ContentTypePath;
import hx.press.model.ContentValue;
import hx.press.model.InstalledPackage;

/** Exercise the same registration, projection and permission contract on every native host. */
class ContentStructureChecks {
    static function check(value:Bool, message:String):Void {
        if (!value) {
            throw new Exception(message);
        }
    }

    public static function run(token:String):Void {
        var slug = "structure-" + token;
        var owner = "plugin-" + slug;
        var key = "structure_" + token;
        var role = "structure_role_" + token;
        InstalledPackage.query.create([
            "id" => owner,
            "kind" => "plugin",
            "slug" => slug,
            "name" => "Structure probe",
            "name_key" => slug,
            "version" => "1.0.0",
            "description" => "Native registration probe",
            "author" => "Tests",
            "directory" => slug,
            "manifest" => Json.stringify({
                apiVersion: CmsVersion.pluginApiVersion,
                cmsVersion: CmsVersion.version,
                kind: "plugin",
                slug: slug,
                name: "Structure probe",
                version: "1.0.0",
                assets: {
                    module: "probe.js"
                },
                fields: [],
                hooks: []
            }),
            "last_error" => "",
            "enabled" => 1,
            "restart_required" => 0,
            "setting_count" => 0,
            "settings" => "{}",
            "installed_at" => SiteSettingsStore.timestamp(),
            "updated_at" => SiteSettingsStore.timestamp()
        ]);
        var input = {
            key: key,
            name: "Probe records",
            singular: "Probe record",
            publicPath: slug,
            dedicatedAccess: true,
            features: [],
            fields: [
                {
                    key: "amount",
                    label: "Amount",
                    kind: "number",
                    inList: true,
                    filterable: true
                },
                {
                    key: "enabled",
                    label: "Enabled",
                    kind: "boolean",
                    inList: true,
                    filterable: true
                }
            ]
        };
        ContentTypes.register(slug, input);
        var type = ContentTypes.find(key);
        check(type != null && type.owner == owner, "Plugin-owned type registration");
        var values = ContentFields.validate(type, {amount: 0, enabled: false}, true);
        var item = ContentItem.query.create([
            "title" => "Native probe",
            "slug" => slug,
            "excerpt" => "",
            "content" => "",
            "category" => "",
            "image" => "",
            "image_alt" => "",
            "status" => "published",
            "content_type" => key,
            "published_at" => "2026-11-04",
            "created_at" => SiteSettingsStore.timestamp(),
            "updated_at" => SiteSettingsStore.timestamp()
        ]);
        ContentFields.save(item.id, type, values);
        var stored = ContentFields.values(item.id, type);
        check(stored.amount == 0 && stored.enabled == false, "Native structured zero/false values");
        var query = ContentItem.query.select(["id", "content_type"]).where("id", item.id);
        ContentFields.projectList(query, type, true);
        var projected = query.first().toObject();
        check(!Reflect.hasField(projected, "content"),
            "ORM projection exposed an unselected constructor default");
        var listed = ContentFields.listValues(projected, type, true);
        check(listed.amount == 0 && listed.enabled == false, "Native correlated field projections");
        Roles.save(role, "Probe role", "", true, [type.capability], true);
        check(Roles.can(role, type.capability) && !Roles.can(role, "settings"),
            "Native role grants");
        check(!Roles.canAssign(role, "owner"), "Native permission ceiling");
        ContentType.query.where("key", key).update(["name" => "Customized records"]);
        ContentCache.changed("structure");
        ContentTypes.register(slug, input);
        check(ContentTypes.find(key).name == "Customized records",
            "Plugin registration overwrote site customization");
        InstalledPackage.query.where("id", owner).update(["enabled" => 0]);
        ContentCache.changed("extensions");
        check(ContentTypes.find(key) == null, "Inactive owner still exposed its collection");
        check(ContentValue.query.where("content_id", item.id).count() == 2,
            "Inactive owner lost structured data");
        InstalledPackage.query.where("id", owner).update(["enabled" => 1]);
        ContentCache.changed("extensions");
        check(ContentTypes.find(key) != null, "Reactivated owner did not restore its collection");
        ContentValue.query.where("content_id", item.id).delete();
        item.delete();
        Roles.remove(role);
        ContentTypePath.query.where("type_key", key).delete();
        ContentType.query.where("key", key).delete();
        Capability.query.where("key", type.capability).delete();
        InstalledPackage.query.where("id", owner).delete();
        ContentCache.changed("structure");
        ContentCache.changed("extensions");
        ContentCache.changed("access");
        ContentCache.contentChanged();
        Sys.println("PASS Native CMS definitions: owned registration, typed/listed values, model projections, role ceilings, disable/re-enable and preserved customizations");
    }
}
