package hx.press.packages;

#if jvm
import hx.press.AdminController;
import hx.press.CmsAccess;
import hx.press.access.Roles;
import hx.press.packages.GitHubReleases.GitHubReleaseError;
import hx.press.view.View;
import hx.press.view.ViewHelpers;
import hx.well.database.Connection;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.ResponseBuilder;

class GitHubPackageController {
    public static function releases(request:Request):AbstractResponse {
        if (!CmsAccess.can("extensions")) {
            return json({error: "Your account cannot install packages."}, 403);
        }
        if (!request.validate([
            "repository" => [Required, String, Max(180)],
            "page" => [Regex("^(?:[1-9][0-9]{0,2}|1000)$")]
        ])) {
            return json({error: "Enter a public GitHub repository URL."}, 422);
        }
        try {
            var repository = GitHubReleases.repository(request.input("repository"));
            var page = Std.parseInt(request.query("page", "1"));
            Connection.free();
            return json(GitHubReleases.list(repository, page));
        } catch (error:GitHubReleaseError) {
            return json({error: error.message}, error.status);
        }
    }

    public static function inspect(request:Request):AbstractResponse {
        var admin = CmsAccess.current();
        if (admin == null || !Roles.can(admin.role, "extensions")) {
            return json({error: "Your account cannot install packages."}, 403);
        }
        if (!request.validate([
            "repository" => [Required, String, Max(180)],
            "asset" => [Required, String, Regex("^[1-9][0-9]{0,17}$")]
        ])) {
            return failed(request, "Choose a GitHub release ZIP.", 422);
        }
        try {
            var repository = GitHubReleases.repository(request.input("repository"));
            var asset:String = request.input("asset");
            var result = PackageManager.stageArchive("plugin", admin.id, destination -> {
                Connection.free();
                return GitHubReleases.inspect(repository, asset, destination);
            });
            result.repository = repository.url;
            if (View.redirectsValidation(request)) {
                // The extensions page shows the staged package and where it came from.
                var source = ViewHelpers.encodeComponent(repository.url);
                return
                    ResponseBuilder.asRedirect('/admin/plugins?inspect=${result.key}&source=${source}',
                        303);
            }
            return json(result, 201);
        } catch (error:GitHubReleaseError) {
            return failed(request, error.message, error.status);
        } catch (error:Dynamic) {
            return failed(request, Std.string(error), 422);
        }
    }

    /** A failed inspection: JSON for scripts, or the release picker again with the error. **/
    static function failed(request:Request, message:String, status:Int):AbstractResponse {
        var repository:Dynamic = request.input("repository", "");
        var requested = Std.string(request.input("release_page", "1"));
        var listed = Std.isOfType(repository,
            String) ? StringTools.trim(repository).substr(0, 180) : "";
        var page = ~/^[1-9][0-9]{0,3}$/.match(requested) ? Std.parseInt(requested) : 1;
        var url = PackageViews.releasesUrl(listed, page);
        var redirect = AdminController.validationRedirect(request, "github", message, url);
        return redirect ?? json({error: message}, status);
    }

    static function json(data:Dynamic, status:Int = 200):AbstractResponse {
        return ResponseBuilder.asJson(data, status).header("Cache-Control", "private, no-store");
    }
}
#end
