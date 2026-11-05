package hx.press.media;

import hx.well.facades.Storage;

/** Managed-image references are platform independent; decoding stays in the upload driver. */
class MediaReferences {
    public static inline var MAX_BYTES = 5 * 1024 * 1024;
    public static final mimeTypes = ["image/jpeg", "image/png", "image/webp", "image/gif"];

    public static function prefix():String {
        var url = Storage.disk("media").url("");
        return StringTools.endsWith(url, "/") ? url : url + "/";
    }

    public static function validFilename(filename:String):Bool {
        return filename != null && ~/^[A-Za-z0-9_-]{32}\.(jpg|png|webp|gif)$/.match(filename);
    }

    public static function imageUrl(value:String):Bool {
        var base = prefix();
        return value != null && StringTools.startsWith(value, base)
            && validFilename(value.substr(base.length));
    }

    public static function storedImage(value:String):Bool {
        return imageUrl(value) && Storage.disk("media").fileExists(value.substr(prefix().length));
    }

    public static function rules():Dynamic {
        var pattern = new StringBuf();
        for (character in prefix().split("")) {
            if ("\\^$.*+?()[]{}|".indexOf(character) >= 0) {
                pattern.add("\\");
            }
            pattern.add(character);
        }
        return {
            uploadUrl: "/admin/media/upload",
            maxBytes: MAX_BYTES,
            mimeTypes: mimeTypes,
            extensions: ["jpg", "jpeg", "png", "webp", "gif"],
            imagePattern: "^" + pattern.toString() + "[A-Za-z0-9_-]{32}\\.(jpg|png|webp|gif)$"
        };
    }
}
