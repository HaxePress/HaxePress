package hx.press.media;

import haxe.crypto.Sha256;
import hx.press.MediaStorage;
import hx.press.model.ImageUpload;
import hx.press.themes.ThemeAssets;
import hx.well.facades.Storage;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.ResponseBuilder;
import hx.well.internal.SecureToken;
#if (target.threaded)
import sys.thread.Mutex;
#else
import hx.well.thread.FakeMutex as Mutex;
#end

class ImageUploads {
    static inline var LIFETIME = 10 * 60 * 1000;
    static inline var MAX_PENDING = 8;
    static final mutex = new Mutex();

    public static function stage(request:Request, userId:Int, credential:String, themeId:String,
            unsupportedStatus:Int = 415):AbstractResponse {
        var bytes = request.bodyBytes;
        if (bytes == null || bytes.length == 0) {
            return ResponseBuilder.asJson({error: "Choose an image to upload."}, 422);
        }
        if (bytes.length > MediaReferences.MAX_BYTES) {
            return ResponseBuilder.asJson({error: "Choose an image smaller than 5 MB."}, 413);
        }
        var format = MediaStorage.format(bytes);
        if (format == null) {
            return ResponseBuilder.asJson({error: "Choose a JPEG, PNG or GIF image."},
                unsupportedStatus);
        }
        var label = request.header("X-File-Name", "");
        try {
            label = StringTools.urlDecode(label).substr(0, 180);
        } catch (_:Dynamic) {
            label = "";
        }
        var ownerHash = Sha256.encode(credential);
        var sha256 = Sha256.make(bytes).toHex();
        return locked(function():AbstractResponse {
            if (themeId != "") {
                ThemeAssets.requireBudget(themeId, 1, bytes.length);
            }
            var now = Date.now().getTime();
            var pending = ImageUpload.query.where("user_id", userId)
                .where("expires_epoch", ">", now)
                .count();
            if (pending >= MAX_PENDING) {
                return
                    ResponseBuilder.asJson({error: "Finish your pending image uploads or wait for them to expire."},
                        429);
            }
            var key = SecureToken.generate(32);
            ImageUpload.query.insert([
                "key" => key,
                "user_id" => userId,
                "owner_hash" => ownerHash,
                "theme_id" => themeId,
                "label" => label,
                "sha256" => sha256,
                "size" => bytes.length,
                "expires_epoch" => now + LIFETIME
            ]);
            var disk = Storage.disk("image_uploads");
            var path = '${key}/image';
            try {
                disk.put(path, bytes);
                return disk.response(path, 'upload.${format.extension}', [
                    "Content-Type" => format.contentType,
                    "Cache-Control" => "private, no-store",
                    "X-Content-Type-Options" => "nosniff",
                    "X-Upload-Id" => key
                ], "attachment").status(202);
            } catch (error:Dynamic) {
                discard(key);
                throw error;
            }
        });
    }

    public static function verify(request:Request, userId:Int, credential:String,
            themeId:String):AbstractResponse {
        if (!request.validate([
            "id" => [Required, String, Custom("cms.token")],
            "sha256" => [Required, String, Regex("^[a-f0-9]{64}$")],
            "width" => [Required, Int, Min(1), Max(10000)],
            "height" => [Required, Int, Min(1), Max(10000)]
        ])) {
            return
                ResponseBuilder.asJson({error: "Supply the image upload ID, hash and dimensions."},
                    422);
        }
        var values = request.only("id", "sha256", "width", "height");
        var key:String = values.get("id");
        var sha256:String = values.get("sha256");
        var width:Int = values.get("width");
        var height:Int = values.get("height");
        if (width * height > MediaStorage.MAX_PIXELS) {
            return ResponseBuilder.asJson({error: "Choose an image under 20 megapixels."}, 422);
        }
        return locked(() -> {
            var upload = ImageUpload.query.select(["label", "sha256", "size"])
                .where("key", key)
                .where("user_id", userId)
                .where("owner_hash", Sha256.encode(credential))
                .where("theme_id", themeId)
                .where("expires_epoch", ">", Date.now().getTime())
                .limit(1)
                .first();
            var disk = Storage.disk("image_uploads");
            var path = '${key}/image';
            if (upload == null || !disk.fileExists(path)) {
                return ResponseBuilder.asJson({error: "This image upload is no longer available."},
                    404);
            }
            if (upload.sha256 != sha256 || disk.size(path) != upload.size
                || upload.size > MediaReferences.MAX_BYTES) {
                return
                    ResponseBuilder.asJson({error: "The uploaded image does not match the verified file."},
                        422);
            }
            var bytes = disk.getBytes(path);
            var format = MediaStorage.format(bytes);
            if (format == null || Sha256.make(bytes).toHex() != sha256) {
                return
                    ResponseBuilder.asJson({error: "The uploaded image does not match the verified file."},
                        422);
            }
            // Claim the file before saving so concurrent confirmations cannot publish it twice.
            disk.move(path, '${key}/verified');
            discard(key);
            var image:Dynamic;
            if (themeId == "") {
                image = MediaStorage.save(bytes, format, {width: width, height: height},
                    upload.label);
            } else {
                image = ThemeAssets.saveImage(themeId, bytes, {
                    extension: format.extension,
                    contentType: format.contentType,
                    width: width,
                    height: height,
                    sha256: sha256
                }, upload.label);
            }
            return ResponseBuilder.asJson(image, 201);
        });
    }

    public static function expire():Void {
        locked(() -> {
            var expired = ImageUpload.query.select(["key"])
                .where("expires_epoch", "<=", Date.now().getTime())
                .orderBy("expires_epoch")
                .limit(100)
                .get();
            for (upload in expired) {
                discard(upload.key);
            }
            return true;
        });
    }

    static function discard(key:String):Void {
        var disk = Storage.disk("image_uploads");
        if (disk.directoryExists(key)) {
            disk.deleteDirectory(key);
        }
        ImageUpload.query.where("key", key).delete();
    }

    static function locked<T>(work:Void->T):T {
        mutex.acquire();
        try {
            var result = work();
            mutex.release();
            return result;
        } catch (error:Dynamic) {
            mutex.release();
            throw error;
        }
    }
}
