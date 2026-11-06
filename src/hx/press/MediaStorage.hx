package hx.press;

import javax.imageio.ImageIO;
import javax.imageio.ImageReader;
import java.io.ByteArrayInputStream;
import haxe.io.Bytes;
import hx.well.facades.Storage;
import hx.well.internal.SecureToken;
import org.commonmark.parser.Parser as MarkdownParser;
import org.commonmark.node.Node as MarkdownNode;
import org.commonmark.node.Image as MarkdownImage;
import hx.press.MediaCatalog;
import hx.press.media.MediaReferences;

using StringTools;

typedef ImageFormat = {extension:String, contentType:String};

typedef StoredImage = {
    id:Int,
    filename:String,
    url:String,
    contentType:String,
    size:Int,
    width:Int,
    height:Int
};

class MediaStorage {
    static final markdown = MarkdownParser.builder().build();
    public static inline var MAX_PIXELS = 20000000;

    public static function contentUsesStoredImages(content:String):Bool {
        try {
            var node:MarkdownNode = markdown.parse(content);
            while (node != null) {
                if (Std.isOfType(node, MarkdownImage)) {
                    var image:MarkdownImage = cast node;
                    if (!MediaReferences.storedImage(image.getDestination())) {
                        return false;
                    }
                }
                if (node.getFirstChild() != null) {
                    node = node.getFirstChild();
                } else {
                    while (node != null && node.getNext() == null) {
                        node = node.getParent();
                    }
                    if (node != null) {
                        node = node.getNext();
                    }
                }
            }
        } catch (error:Dynamic) {
            return false;
        }
        return true;
    }

    public static function format(bytes:Bytes):Null<ImageFormat> {
        if (bytes.length >= 8 && bytes.sub(0, 8).toHex() == "89504e470d0a1a0a")
            return {extension: "png", contentType: "image/png"};
        if (bytes.length >= 3 && bytes.get(0) == 255 && bytes.get(1) == 216 && bytes.get(2) == 255)
            return {extension: "jpg", contentType: "image/jpeg"};
        if (bytes.length >= 6 && ["GIF87a", "GIF89a"].contains(bytes.getString(0, 6)))
            return {extension: "gif", contentType: "image/gif"};
        return null;
    }

    public static function dimensions(bytes:Bytes):Null<{width:Int, height:Int}> {
        var input = ImageIO.createImageInputStream(cast new ByteArrayInputStream(bytes.getData()));
        if (input == null)
            return null;
        var reader:ImageReader = null;
        var result:Null<{width:Int, height:Int}> = null;
        try {
            var readers = ImageIO.getImageReaders(cast input);
            if (readers.hasNext()) {
                reader = readers.next();
                reader.setInput(cast input, false, true);
                var width = reader.getWidth(0);
                var height = reader.getHeight(0);
                if (width > 0
                    && height > 0
                    && width <= 10000
                    && height <= 10000
                    && width * 1.0 * height <= MAX_PIXELS) {
                    result = {width: width, height: height};
                }
            }
        } catch (error:Dynamic) {
            result = null;
        }
        if (reader != null)
            reader.dispose();
        input.close();
        return result;
    }

    public static function save(bytes:Bytes, format:ImageFormat,
            dimensions:{width:Int, height:Int}, label:String = ""):StoredImage {
        var disk = Storage.disk("media");
        disk.makeDirectory("");
        var filename = '${SecureToken.generate(32)}.${format.extension}';
        while (disk.exists(filename))
            filename = '${SecureToken.generate(32)}.${format.extension}';
        disk.put(filename, bytes);
        var image:StoredImage = {
            id: 0,
            filename: filename,
            url: disk.url(filename),
            contentType: format.contentType,
            size: bytes.length,
            width: dimensions.width,
            height: dimensions.height
        };
        try {
            image.id = MediaCatalog.register(image, label);
            return image;
        } catch (error:Dynamic) {
            disk.delete(filename);
            throw error;
        }
    }
}
