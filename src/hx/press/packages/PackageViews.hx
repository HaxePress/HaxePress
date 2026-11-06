package hx.press.packages;

import hx.press.CmsAccess;
import hx.press.i18n.I18n;
import hx.press.i18n.I18n.TranslationProps;
import hx.press.i18n.TranslationCatalogue;
import hx.press.model.InstalledPackage;
import hx.press.model.PackageUpload;
import hx.press.view.ViewAssets;
import hx.press.view.ViewHelpers;
import hx.well.http.Request;
#if jvm
import hx.press.packages.GitHubReleases.GitHubReleaseError;
import hx.well.database.Connection;
#end

/**
    Presentation data of `Admin/Extensions`: localized package names,
    theme thumbnail sources, a staged upload's inspection and the GitHub
    release picker, which the React page used to keep in browser state.
**/
class PackageViews {
    static final uploadKey = ~/^[A-Za-z0-9_-]{32}$/;
    static final releasePage = ~/^(?:[1-9][0-9]{0,2}|1000)$/;

    /** The listed packages with their names and summaries in the current locale. **/
    public static function packages(items:Array<Dynamic>, translations:TranslationProps,
            kind:String, snapshot:String):Array<Dynamic> {
        var core = translations.catalogues.get("cms");
        var admin = CmsAccess.current();
        var actor = admin == null ? "" : Std.string(admin.id);
        var assets = ViewAssets.version();
        for (item in items) {
            var own = translations.catalogues.get(item.id);
            var name:String = item.name;
            var description:String = item.description;
            item.localizedName = translate(own, core, name);
            item.localizedDescription = description == "" ? "" : translate(own, core, description);
            item.thumbnail = kind == "theme" ? thumbnail(item, translations.locale, snapshot,
                assets, actor) : "";
        }
        return items;
    }

    static function translate(own:Null<Map<String, Dynamic>>, core:Null<Map<String, Dynamic>>,
            key:String):String {
        var message:Dynamic = own == null ? null : own.get(key);
        if (message == null && core != null) {
            message = core.get(key);
        }
        return TranslationCatalogue.format(message, key, null);
    }

    /**
        The preview frame a theme card captures. Its query keys the browser's
        thumbnail cache: the theme revision, locale, content snapshot, front
        end build and viewer, as the React thumbnail did.
    **/
    static function thumbnail(item:Dynamic, locale:String, snapshot:String, assets:String,
            actor:String):String {
        var values = [
            "revision" => Std.string(item.updated_at),
            "lang" => locale,
            "snapshot" => snapshot,
            "assets" => assets,
            "actor" => actor
        ];
        var pairs = [
            for (key in ["revision", "lang", "snapshot", "assets", "actor"])
                '${key}=${ViewHelpers.encodeComponent(values.get(key))}'
        ];
        return '/admin/themes/${item.id}/preview/frame?${pairs.join("&")}';
    }

    /** The staged upload named by `?inspect=`, when it belongs to this account and has not expired. **/
    public static function inspection(request:Request, kind:String):Null<Dynamic> {
        var key = request.query("inspect", "");
        var admin = CmsAccess.current();
        if (admin == null || !uploadKey.match(key)) {
            return null;
        }
        var upload = PackageUpload.query.select(["key", "manifest"])
            .where("key", key)
            .where("user_id", admin.id)
            .where("kind", kind)
            .where("expires_epoch", ">", Date.now().getTime())
            .limit(1)
            .first();
        if (upload == null) {
            return null;
        }
        var manifest = try PackageManifest.parse(upload.manifest) catch (_:Dynamic) null;
        if (manifest == null) {
            return null;
        }
        var existing = InstalledPackage.query.select(["version"])
            .where("id", '${kind}-${manifest.slug}')
            .limit(1)
            .first();
        var target = PackageManifest.serverArtifact(manifest) == "" ? "" : PackageManifest.serverTarget();
        var serverLabel = switch target {
            case "jvm": "Includes a JVM/JAR server module";
            case "cpp": "Includes a C++/CPPIA server module";
            case "php": "Includes a PHP server module";
            default: "Frontend package";
        };
        var installedVersion = existing == null ? "" : existing.version;
        return {
            key: key,
            name: manifest.name,
            version: manifest.version,
            description: manifest.description,
            author: manifest.author,
            serverLabel: serverLabel,
            repository: repository(request.query("source", "")),
            installedVersion: installedVersion,
            builder: manifest.layout == "builder",
            replace: installedVersion == "" ? "0" : "1"
        };
    }

    /** A GitHub repository URL in its canonical form, or empty. **/
    static function repository(value:String):String {
        #if jvm
        if (value == "") {
            return "";
        }
        return try GitHubReleases.repository(value).url catch (_:Dynamic) "";
        #else
        return "";
        #end
    }

    /** The release picker opened with `?github=1`, listing `?repository=` releases. **/
    public static function github(request:Request, kind:String):Null<Dynamic> {
        #if jvm
        if (kind != "plugin" || request.query("github", "") != "1") {
            return null;
        }
        var input = StringTools.trim(request.query("repository", "")).substr(0, 180);
        var requested = request.query("release_page", "1");
        var number = releasePage.match(requested) ? Std.parseInt(requested) : 1;
        var picker:Dynamic = {
            repository: input,
            error: "",
            page: Std.string(number),
            loaded: false,
            releases: [],
            previous: null,
            next: null
        };
        if (input == "") {
            return picker;
        }
        try {
            var source = GitHubReleases.repository(input);
            Connection.free();
            var listing = GitHubReleases.list(source, number);
            var prerelease = I18n.t("Pre-release");
            picker.releases = [
                for (release in listing.releases)
                    {
                        label: releaseLabel(release.name, release.tag, release.prerelease,
                            prerelease),
                        assets: [
                            for (asset in release.assets)
                                {
                                    id: asset.id,
                                    name: asset.name
                                }
                        ]
                    }
            ];
            picker.loaded = true;
            if (listing.page > 1) {
                picker.previous = releasesUrl(input, listing.page - 1);
            }
            if (listing.nextPage != null) {
                picker.next = releasesUrl(input, listing.nextPage);
            }
        } catch (error:GitHubReleaseError) {
            picker.error = error.message;
        } catch (error:Dynamic) {
            picker.error = "GitHub releases are temporarily unavailable.";
        }
        return picker;
        #else
        return null;
        #end
    }

    static function releaseLabel(name:String, tag:String, prerelease:Bool,
            prereleaseLabel:String):String {
        var prefix = name != "" && name != tag ? '${name} · ' : "";
        var channel = prerelease ? ' · ${prereleaseLabel}' : "";
        return '${prefix}${tag}${channel}';
    }

    public static function releasesUrl(repository:String, page:Int):String {
        var encoded = ViewHelpers.encodeComponent(repository);
        return '/admin/plugins?github=1&repository=${encoded}&release_page=${page}';
    }
}
