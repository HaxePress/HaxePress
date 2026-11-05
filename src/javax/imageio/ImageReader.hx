package javax.imageio;

import java.lang.Object;
import java.awt.image.BufferedImage;

@:native("javax.imageio.ImageReader")
extern class ImageReader {
    public function setInput(input:Object, seekForwardOnly:Bool, ignoreMetadata:Bool):Void;
    public function getWidth(imageIndex:Int):Int;
    public function getHeight(imageIndex:Int):Int;
    public function read(imageIndex:Int):BufferedImage;
    public function dispose():Void;
}
