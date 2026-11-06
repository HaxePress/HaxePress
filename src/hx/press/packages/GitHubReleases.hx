package hx.press.packages;

#if jvm
import haxe.Exception;
import haxe.Json;
import haxe.Timer;
import haxe.io.Bytes;
import hx.press.CmsVersion;
import hx.press.packages.SafePackageArchive.InspectedPackage;
import hx.well.facades.Cache;
import hx.well.facades.Storage;
import hx.well.storage.StorageDisk;
import java.io.InputStream;
import java.io.NativeInput;
import java.net.HttpURLConnection;
import java.net.URI;
import java.security.DigestInputStream;
import java.security.MessageDigest;

typedef GitHubRepository = {
    var path:String;
    var url:String;
}

private typedef GitHubAsset = {
    var id:String;
    var name:String;
    var size:Int;
}

private typedef GitHubRelease = {
    var tag:String;
    var name:String;
    var prerelease:Bool;
    var assets:Array<GitHubAsset>;
}

typedef GitHubReleasePage = {
    var repository:String;
    var releases:Array<GitHubRelease>;
    var page:Int;
    var nextPage:Null<Int>;
}

class GitHubReleaseError extends Exception {
    public final status:Int;

    public function new(message:String, status:Int = 422) {
        super(message);
        this.status = status;
    }
}

class GitHubReleases {
    public static inline var MAX_PAGE = 1000;
    static inline var PAGE_SIZE = 10;
    static inline var MAX_METADATA_BYTES = 2 * 1024 * 1024;
    static inline var API_HOST = "api.github.com";
    static final downloadHosts = [
        "github.com",
        "release-assets.githubusercontent.com",
        "objects.githubusercontent.com",
        "github-releases.githubusercontent.com"
    ];

    public static function repository(value:String):GitHubRepository {
        var pattern = ~/^https:\/\/github\.com\/([A-Za-z0-9][A-Za-z0-9-]{0,38})\/([A-Za-z0-9_.-]{1,100})(?:\/releases)?\/?$/i;
        if (!pattern.match(StringTools.trim(value))) {
            throw new GitHubReleaseError("Enter a public GitHub repository URL.");
        }
        var owner = pattern.matched(1).toLowerCase();
        var name = pattern.matched(2).toLowerCase();
        if (StringTools.endsWith(name, ".git")) {
            name = name.substr(0, name.length - 4);
        }
        if (name == "" || name == "." || name == "..") {
            throw new GitHubReleaseError("Enter a public GitHub repository URL.");
        }
        var path = '${owner}/${name}';
        return {path: path, url: 'https://github.com/${path}'};
    }

    public static function list(repository:GitHubRepository, page:Int):GitHubReleasePage {
        var key = 'cms:github-releases:${repository.path}:${page}';
        return Cache.store().remember(key, 120, () -> {
            var result = metadata(repository, '/releases?per_page=${PAGE_SIZE}&page=${page}');
            if (!Std.isOfType(result.data, Array)) {
                throw unavailable();
            }
            var records:Array<Dynamic> = result.data;
            var releases:Array<GitHubRelease> = [];
            for (record in records) {
                var tag = text(record, "tag_name", 255);
                var entries:Dynamic = Reflect.field(record, "assets");
                if (Reflect.field(record, "draft") == true || tag == ""
                    || !Std.isOfType(entries, Array)) {
                    continue;
                }
                var assets = [];
                for (entry in (cast entries : Array<Dynamic>)) {
                    var asset = zipAsset(entry);
                    if (asset != null) {
                        assets.push(asset);
                    }
                }
                if (assets.length > 0) {
                    releases.push({
                        tag: tag,
                        name: text(record, "name", 255),
                        prerelease: Reflect.field(record, "prerelease") == true,
                        assets: assets
                    });
                }
            }
            return {
                repository: repository.url,
                releases: releases,
                page: page,
                nextPage: result.hasNext && page < MAX_PAGE ? page + 1 : null};
        });
    }

    public static function inspect(repository:GitHubRepository, assetId:String,
            destination:String):InspectedPackage {
        if (!~/^[1-9][0-9]{0,17}$/.match(assetId)) {
            throw new GitHubReleaseError("Choose a GitHub release ZIP.");
        }
        var data = metadata(repository, '/releases/assets/${assetId}').data;
        var asset = zipAsset(data);
        if (asset == null || asset.id != assetId) {
            throw new GitHubReleaseError("Choose an uploaded release ZIP no larger than 64 MB.");
        }
        var url = text(data, "browser_download_url", 4096);
        var address = parseUri(url);
        if (address.getHost() != "github.com"
            || address.getRawQuery() != null
            || !~/^\/[^\/]+\/[^\/]+\/releases\/download\/.+\.zip$/i.match(address.getRawPath())) {
            throw unavailable();
        }
        var digest = text(data, "digest", 80);
        var disk = Storage.disk("extensions");
        var archive = '${destination}.zip';
        try {
            download(address, disk, archive, asset.size, digest);
            var inspected = SafePackageArchive.extractFile(disk, archive, destination);
            disk.delete(archive);
            return inspected;
        } catch (error:Dynamic) {
            if (disk.fileExists(archive)) {
                disk.delete(archive);
            }
            throw error;
        }
    }

    static function zipAsset(record:Dynamic):Null<GitHubAsset> {
        var name = text(record, "name", 255);
        var url = text(record, "url", 512);
        var size:Dynamic = Reflect.field(record, "size");
        var identifier = ~/\/releases\/assets\/([1-9][0-9]{0,17})$/;
        if (Reflect.field(record, "state") != "uploaded"
            || !StringTools.endsWith(name.toLowerCase(), ".zip")
            || !Std.isOfType(size, Int)
            || size < 4
            || size > SafePackageArchive.MAX_BYTES
            || !identifier.match(url)) {
            return null;
        }
        return {id: identifier.matched(1), name: name, size: size};
    }

    static function text(record:Dynamic, field:String, maximum:Int):String {
        var value:Dynamic = Reflect.field(record, field);
        return Std.isOfType(value, String) ? (cast value : String).substr(0, maximum) : "";
    }

    static function metadata(repository:GitHubRepository,
            path:String):{data:Dynamic, hasNext:Bool} {
        var url = 'https://${API_HOST}/repos/${repository.path}${path}';
        var connection = connect(parseUri(url), true);
        var input:Null<GitHubInput> = null;
        try {
            var link = connection.getHeaderField("Link");
            input = new GitHubInput(connection.getInputStream(), MAX_METADATA_BYTES, 15);
            var data = Json.parse(input.readAll(8192).toString());
            input.close();
            connection.disconnect();
            return {data: data, hasNext: link != null && link.indexOf('rel="next"') >= 0};
        } catch (_:Dynamic) {
            if (input != null) {
                try
                    input.close()
                catch (_:Dynamic) {}
            }
            connection.disconnect();
            throw unavailable();
        }
    }

    static function download(address:URI, disk:StorageDisk, path:String, size:Int,
            digest:String):Void {
        var connection = connect(address, false);
        var expectedLength = connection.getContentLength();
        if (expectedLength >= 0 && expectedLength != size) {
            connection.disconnect();
            throw new GitHubReleaseError("The GitHub release ZIP size changed. Load releases again.");
        }
        var checksum = MessageDigest.getInstance("SHA-256");
        var input:Null<GitHubInput> = null;
        try {
            var source = new DigestInputStream(connection.getInputStream(), checksum);
            input = new GitHubInput(source, size, 60);
            disk.writeStream(path, input, "private");
            input.close();
            connection.disconnect();
        } catch (_:Dynamic) {
            if (input != null) {
                try
                    input.close()
                catch (_:Dynamic) {}
            }
            connection.disconnect();
            throw new GitHubReleaseError("The GitHub release ZIP could not be downloaded.", 502);
        }
        var hash = Bytes.ofData(checksum.digest()).toHex();
        if (disk.size(path) != size || (digest != "" && digest.toLowerCase() != 'sha256:${hash}')) {
            throw new GitHubReleaseError("The GitHub release ZIP did not match its published size or checksum.");
        }
    }

    static function parseUri(value:String):URI {
        try {
            return new URI(value);
        } catch (_:Dynamic) {
            throw unavailable();
        }
    }

    static function connect(address:URI, metadata:Bool):HttpURLConnection {
        var allowed = metadata ? [API_HOST] : downloadHosts;
        for (_ in 0...4) {
            var host = address.getHost();
            var port = address.getPort();
            if (address.getScheme() != "https"
                || host == null
                || !allowed.contains(host.toLowerCase())
                || (port != -1 && port != 443)
                || address.getUserInfo() != null
                || address.getRawFragment() != null) {
                throw unavailable();
            }
            var connection:HttpURLConnection = null;
            try {
                connection = cast address.toURL().openConnection();
                connection.setInstanceFollowRedirects(false);
                connection.setConnectTimeout(5000);
                connection.setReadTimeout(10000);
                connection.setRequestProperty("User-Agent", 'HaxePress/${CmsVersion.version}');
                if (metadata) {
                    connection.setRequestProperty("Accept", "application/vnd.github+json");
                    connection.setRequestProperty("X-GitHub-Api-Version", "2026-03-10");
                }
                var status = connection.getResponseCode();
                if (status == 200) {
                    return connection;
                }
                var location = connection.getHeaderField("Location");
                connection.disconnect();
                connection = null;
                if ([301, 302, 303, 307, 308].contains(status) && location != null) {
                    address = address.resolve(location);
                } else if (status == 404) {
                    throw new GitHubReleaseError("This public GitHub repository or release asset could not be found.",
                        404);
                } else if (metadata && (status == 403 || status == 429)) {
                    throw new GitHubReleaseError("GitHub is limiting release requests. Try again later.",
                        429);
                } else {
                    throw unavailable();
                }
            } catch (error:Dynamic) {
                if (connection != null) {
                    connection.disconnect();
                }
                if (Std.isOfType(error, GitHubReleaseError)) {
                    throw error;
                }
                throw unavailable();
            }
        }
        throw unavailable();
    }

    static function unavailable():GitHubReleaseError {
        return new GitHubReleaseError("GitHub releases are temporarily unavailable.", 502);
    }
}

private class GitHubInput extends NativeInput {
    final limit:Int;
    final deadline:Float;
    var received = 0;

    public function new(stream:InputStream, limit:Int, seconds:Int) {
        super(stream);
        this.limit = limit;
        deadline = Timer.stamp() + seconds;
    }

    override public function readBytes(bytes:Bytes, position:Int, length:Int):Int {
        if (Timer.stamp() > deadline) {
            throw new Exception("The GitHub response timed out.");
        }
        var count = super.readBytes(bytes, position,
            Std.int(Math.min(length, limit - received + 1)));
        received += count;
        if (received > limit) {
            throw new Exception("The GitHub response exceeded its size limit.");
        }
        return count;
    }
}
#end
