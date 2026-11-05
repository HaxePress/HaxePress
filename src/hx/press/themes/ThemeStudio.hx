package hx.press.themes;

import haxe.Exception;
import haxe.Json;
import haxe.crypto.Md5;
import hx.press.Activity;
import hx.press.CategoryData;
import hx.press.CmsVersion;
import hx.press.ContentCache;
import hx.press.SiteSettingsStore;
import hx.press.media.MediaDependencies;
import hx.press.model.InstalledPackage;
import hx.press.model.ThemeDesign;
import hx.press.model.ContentType;
import hx.press.packages.PackageManager;
import hx.well.facades.DBStatic;
import hx.well.internal.SecureToken;

class ThemeStudio {
    public static function create(name:String, blank:Bool, userId:Int, userName:String,
            source:String = ""):String {
        var design:Dynamic = source == "" ? ThemeDesignSchema.starter(blank) : ThemeDesignSchema.parse(source);
        var dependencies:Null<MediaDependencies> = null;
        var created = false;
        PackageManager.writes.acquire("packages");
        try {
            var slug = "studio-" + Md5.encode(SecureToken.generate(32)).substr(0, 12);
            var id = "theme-" + slug;
            var now = SiteSettingsStore.timestamp();
            var manifest = {
                apiVersion: CmsVersion.pluginApiVersion,
                cmsVersion: CmsVersion.version,
                kind: "theme",
                slug: slug,
                name: name,
                version: "1.0.0",
                description: "",
                author: userName,
                layout: "builder",
                hooks: [],
                fields: []
            };
            if (InstalledPackage.query.where("id", id).exists()) {
                throw new Exception("This design identifier is already in use. Try creating it again.");
            }
            ThemeAssets.requireDesign(id, design);
            dependencies = MediaDependencies.forTheme(slug);
            dependencies.withValue("design-draft", design, () -> {
                DBStatic.transaction(() -> {
                    InstalledPackage.query.create([
                        "id" => id,
                        "kind" => "theme",
                        "slug" => slug,
                        "name" => name,
                        "name_key" => CategoryData.key(name),
                        "version" => "1.0.0",
                        "description" => "",
                        "author" => userName,
                        "directory" => slug,
                        "manifest" => Json.stringify(manifest),
                        "enabled" => 0,
                        "setting_count" => 0,
                        "settings" => "{}",
                        "last_error" => "",
                        "restart_required" => 0,
                        "installed_at" => now,
                        "updated_at" => now
                    ]);
                    ThemeDesign.query.create([
                        "id" => id,
                        "draft" => Json.stringify(design),
                        "published" => "",
                        "version" => 1,
                        "published_version" => 0,
                        "updated_at" => now
                    ]);
                    Activity.append(userId, userName, "created", "theme", 0, name);
                });
                created = true;
                return true;
            }, name + " (design draft)");
            ContentCache.changed("extensions");
            PackageManager.writes.release("packages");
            return id;
        } catch (error:Dynamic) {
            if (!created && dependencies != null) {
                try {
                    dependencies.forget("design-draft");
                } catch (_:Dynamic) {}
            }
            PackageManager.writes.release("packages");
            throw error;
        }
    }

    public static function save(id:String, name:String, source:String, version:Int, publish:Bool,
            userId:Int, userName:String):{
        version:Int,
        published_version:Int
    } {
        var document:Dynamic = ThemeDesignSchema.parse(source);
        var serialized = Json.stringify(document);
        PackageManager.writes.acquire("packages");
        try {
            var packageData = InstalledPackage.query.select(["slug", "manifest"])
                .where("id", id)
                .where("kind", "theme")
                .limit(1)
                .first();
            var current = ThemeDesign.query.select(["version", "published_version"])
                .where("id", id)
                .limit(1)
                .first();
            if (packageData == null || current == null) {
                throw new Exception("This theme is no longer available.");
            }
            if (current.version != version) {
                throw new Exception("This theme was changed in another editor. Reload before saving your changes.");
            }
            var nextVersion = current.version + 1;
            var now = SiteSettingsStore.timestamp();
            var manifest:Dynamic = Json.parse(packageData.manifest);
            manifest.name = name;
            if (publish) {
                requireTemplates(document, manifest);
                manifest.templates = templateDefinitions(document);
            }
            var dependencies = MediaDependencies.forTheme(packageData.slug);
            var write = () -> {
                return ThemeAssets.locked(id, () -> {
                    ThemeAssets.requireDesign(id, document);
                    DBStatic.transaction(() -> {
                        var values:Map<String,
                            Dynamic> = ["draft" => serialized, "version" => nextVersion, "updated_at" => now];
                        if (publish) {
                            values.set("published", serialized);
                            values.set("published_version", nextVersion);
                        }
                        ThemeDesign.query.where("id", id).update(values);
                        InstalledPackage.query.where("id", id).update([
                            "name" => name,
                            "name_key" => CategoryData.key(name),
                            "manifest" => Json.stringify(manifest),
                            "updated_at" => now
                        ]);
                        Activity.append(userId, userName, publish ? "published" : "saved",
                            "theme", 0, name);
                    });
                    return true;
                });
            };
            dependencies.withValue("design-draft", document, () -> {
                return publish ? dependencies.withValue("design-published", document, write,
                    name + " (published design)") : write();
            }, name + " (design draft)");
            ContentCache.changed("extensions");
            var result = {
                version: nextVersion,
                published_version: publish ? nextVersion : current.published_version
            };
            PackageManager.writes.release("packages");
            try {
                ThemeCollaboration.designChanged(id, result.version, result.published_version);
            } catch (_:Dynamic) {
                trace("A saved theme change could not be delivered to every editor.");
            }
            return result;
        } catch (error:Dynamic) {
            PackageManager.writes.release("packages");
            throw error;
        }
    }

    public static function templateDefinitions(document:Dynamic):Array<{name:String, label:String, scope:String}> {
        var templates = [];
        for (template in Reflect.fields(document.templateMeta)) {
            var metadata = Reflect.field(document.templateMeta, template);
            var scope = switch (metadata.fallback) {
                case "Home": "home";
                case "ContentIndex": "archive";
                default: "detail";
            };
            templates.push({name: template, label: metadata.label, scope: scope});
        }
        return templates;
    }

    public static function requireTemplates(document:Dynamic, previous:Dynamic):Void {
        var templates:Array<Dynamic> = previous.templates ?? [];
        var removed = templates.filter(template -> !Reflect.hasField(document.templates,
            template.name))
            .map(template -> (cast template.name : String));
        if (removed.length == 0) {
            return;
        }
        var homeTemplate = SiteSettingsStore.settings().get("home_template") ?? "Home";
        var assigned = ContentType.query.where(query -> query.whereIn("template", cast removed)
            .orWhereIn("archive_template", cast removed))
            .exists();
        if (removed.contains(homeTemplate) || assigned) {
            throw new Exception("A removed template is still assigned to CMS content or homepage settings. Choose another template first.");
        }
    }
}
