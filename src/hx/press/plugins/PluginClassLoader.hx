package hx.press.plugins;

#if jvm
import java.lang.Class as JavaClass;
import java.lang.ClassLoader;
import java.lang.ClassNotFoundException;
import java.net.URL;
import java.net.URLClassLoader;
import java.util.concurrent.locks.ReentrantLock;
import java.NativeArray;

/** Shares the stable API/runtime while isolating Haxe's per-build anonymous class names. */
@:nativeGen
class PluginClassLoader extends URLClassLoader {
    var generatedClassesLock:ReentrantLock = new ReentrantLock();

    public function new(urls:NativeArray<URL>, parent:ClassLoader) {
        super(urls, parent);
    }

    overload override public function loadClass(name:String, resolve:Bool):JavaClass<Dynamic> {
        if (!StringTools.startsWith(name, "haxe.generated.")) {
            return super.loadClass(name, resolve);
        }
        generatedClassesLock.lock();
        try {
            var loaded = findLoadedClass(name);
            if (loaded == null) {
                try {
                    loaded = findClass(name);
                } catch (missing:ClassNotFoundException) {
                    loaded = super.loadClass(name, resolve);
                }
            }
            if (resolve) {
                resolveClass(loaded);
            }
            generatedClassesLock.unlock();
            return loaded;
        } catch (error:Dynamic) {
            generatedClassesLock.unlock();
            throw error;
        }
    }
}
#end
