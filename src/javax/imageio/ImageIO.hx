package javax.imageio;

import java.lang.Object;
import javax.imageio.stream.ImageInputStream;
import java.util.Iterator;

@:native("javax.imageio.ImageIO")
extern class ImageIO {
    public static function createImageInputStream(input:Object):ImageInputStream;
    public static function getImageReaders(input:Object):Iterator<ImageReader>;
}
