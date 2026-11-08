package hx.press.packages;

import hx.press.packages.PackageManifest.ManifestData;
import haxe.Exception;
import haxe.io.Bytes;
import hx.well.facades.Storage;
import hx.well.storage.StorageDisk;
import haxe.io.Eof;
import hx.press.packages.PackageEntryInput.ArchiveBudget;
import hx.press.i18n.TranslationCatalogue;
import hx.press.plugins.PhpModuleDefinition;
#if (jvm || (php && !cms_plugin))
import hx.press.themes.ThemeDesignPackage;
import hx.press.view.PluginViews;
import hx.press.view.ThemeViews;
#end
#if jvm
import java.io.ByteArrayInputStream;
import java.io.FileInputStream;
import java.io.InputStream;
import java.util.jar.JarFile;
import java.util.zip.ZipInputStream;
import java.NativeString;
import java.util.Locale;
#end

typedef InspectedPackage = {
    var root:String;
    var manifest:ManifestData;
}

class SafePackageArchive {
    public static inline var MAX_BYTES = 64 * 1024 * 1024;
    public static inline var MAX_EXPANDED_BYTES = 128 * 1024 * 1024;
    public static inline var MAX_FILE_BYTES = 16 * 1024 * 1024;
    public static inline var MAX_FILES = 256;

    public static function extract(bytes:Bytes, destination:String,
            ?disk:StorageDisk):InspectedPackage {
        if (disk == null) {
            disk = Storage.disk("extensions");
        }
        prepare(disk, destination, bytes.length);
        #if jvm
        return unpackJvm(new ByteArrayInputStream(bytes.getData()), disk, destination);
        #elseif (cpp || php)
        try {
            PortablePackageArchive.unpack(bytes, destination, disk);
            return inspect(disk, packageRoot(disk, destination));
        } catch (error:Dynamic) {
            disk.deleteDirectory(destination);
            throw error;
        }
        #else
        disk.deleteDirectory(destination);
        throw new Exception("Package uploads require a JVM, C++ or PHP host.");
        #end
    }

    static function prepare(disk:StorageDisk, destination:String, size:Int):Void {
        if (!PackageManifest.safePath(destination)
            || size < 4
            || size > MAX_BYTES
            || disk.exists(destination)) {
            throw new Exception("Choose a ZIP package smaller than 64 MB.");
        }
        disk.makeDirectory(destination);
    }

    #if jvm
    public static function extractFile(disk:StorageDisk, path:String,
            destination:String):InspectedPackage {
        prepare(disk, destination, disk.size(path));
        var source:FileInputStream;
        try {
            source = new FileInputStream(disk.path(path));
        } catch (error:Dynamic) {
            disk.deleteDirectory(destination);
            throw error;
        }
        return unpackJvm(source, disk, destination);
    }

    static function unpackJvm(source:InputStream, disk:StorageDisk,
            destination:String):InspectedPackage {
        var input = new ZipInputStream(source);
        var budget:ArchiveBudget = {bytes: 0};
        var count = 0;
        var seen:Map<String, Bool> = [];
        var buffer = Bytes.alloc(8192);
        try {
            var entry = input.getNextEntry();
            while (entry != null) {
                count++;
                if (count > MAX_FILES) {
                    throw new Exception("The package contains more than 256 files and directories.");
                }
                var name = entry.getName();
                if (entry.isDirectory() && StringTools.endsWith(name, "/")) {
                    name = name.substr(0, name.length - 1);
                }
                if (!PackageManifest.safePath(name)) {
                    throw new Exception("The package contains an unsafe file path.");
                }
                var nativeName:NativeString = cast name;
                var key:String = nativeName.toLowerCase(Locale.ROOT);
                if (seen.exists(key)) {
                    throw new Exception("The package contains duplicate file paths.");
                }
                seen.set(key, true);
                var path = '${destination}/${name}';
                var stream = new PackageEntryInput((bytes, position,
                        length) -> input.read(bytes.getData(), position, length),
                    budget, entry.isDirectory());
                if (entry.isDirectory()) {
                    disk.makeDirectory(path);
                    try {
                        while (true) {
                            stream.readBytes(buffer, 0, buffer.length);
                        }
                    } catch (_:Eof) {}
                } else {
                    disk.writeStream(path, stream);
                }
                input.closeEntry();
                entry = input.getNextEntry();
            }
            input.close();
            var root = packageRoot(disk, destination);
            return inspect(disk, root);
        } catch (error:Dynamic) {
            input.close();
            disk.deleteDirectory(destination);
            throw error;
        }
    }
    #end

    public static function inspect(disk:StorageDisk, root:String):InspectedPackage {
        var manifest = PackageManifest.parseUpload(disk.get('${root}/${PackageManifest.FILENAME}'));
        for (asset in [manifest.module, manifest.stylesheet]) {
            if (asset != ""
                && (!disk.fileExists('${root}/public/${asset}')
                    || disk.directoryExists('${root}/public/${asset}'))) {
                throw new Exception("The package is missing a declared frontend asset.");
            }
        }
        if (manifest.legacyRenderer) {
            throw new Exception(PackageManifest.RENDERER_UNSUPPORTED);
        }
        if (manifest.views != "") {
            // The JVM and PHP applications include Wellout; plugin test hosts do not.
            #if (jvm || (php && !cms_plugin))
            if (manifest.kind == "theme") {
                ThemeViews.inspectPackage(disk, '${root}/${manifest.views}');
            } else {
                PluginViews.inspectPackage(disk, '${root}/${manifest.views}');
            }
            #else
            throw new Exception("Packages with Wellout templates require the HaxePress application.");
            #end
        }
        PackageManifest.serverArtifact(manifest);
        if (manifest.layout == "builder") {
            #if (jvm || (php && !cms_plugin))
            ThemeDesignPackage.inspect(root, manifest);
            #else
            throw new Exception("Visual theme package installation requires the HaxePress application.");
            #end
        }
        for (locale => catalogue in manifest.translations) {
            var path = '${root}/${catalogue}';
            if (!disk.fileExists(path) || disk.directoryExists(path)
                || disk.size(path) > TranslationCatalogue.MAX_BYTES) {
                throw new Exception('The package is missing a bounded translation catalogue: ${locale}');
            }
            TranslationCatalogue.parse(disk.get(path));
        }
        for (artifact in [manifest.serverJar, manifest.serverCppia, manifest.serverPhp]) {
            if (artifact != "") {
                var path = '${root}/${artifact}';
                if (!disk.fileExists(path)
                    || disk.directoryExists(path)
                    || disk.size(path) < 5
                    || disk.size(path) > MAX_FILE_BYTES) {
                    throw new Exception("The package is missing a valid server module file.");
                }
            }
        }
        if (manifest.serverPhp != "") {
            PhpModuleDefinition.inspect(disk, '${root}/${manifest.serverPhp}', manifest.entrypoint);
        }
        if (manifest.serverCppia != "") {
            var input = disk.readStream('${root}/${manifest.serverCppia}');
            var magic = input.readString(5);
            input.close();
            if (magic != "CPPIA" && magic != "CPPIB") {
                throw new Exception("The server CPPIA file has an invalid bytecode header.");
            }
        }
        #if jvm
        if (manifest.serverJar != "") {
            inspectJar(disk.path('${root}/${manifest.serverJar}'), manifest.entrypoint);
        }
        #end
        return {root: root, manifest: manifest};
    }

    static function packageRoot(disk:StorageDisk, directory:String):String {
        if (disk.fileExists('${directory}/${PackageManifest.FILENAME}')) {
            return directory;
        }
        var files = disk.files(directory);
        var directories = disk.directories(directory);
        if (files.length == 0 && directories.length == 1) {
            var nested = directories[0];
            if (disk.fileExists('${nested}/${PackageManifest.FILENAME}')) {
                return nested;
            }
        }
        throw new Exception('The ZIP package must include ${PackageManifest.FILENAME}.');
    }

    #if jvm
    static function inspectJar(path:String, entrypoint:String):Void {
        var jar = new JarFile(path);
        try {
            var entry = jar.getJarEntry('${entrypoint.split(".").join("/")}.class');
            if (entry == null || entry.getSize() > 1024 * 1024) {
                throw new Exception("The server JAR is missing a valid entrypoint class.");
            }
            jar.close();
        } catch (error:Dynamic) {
            jar.close();
            throw error;
        }
    }
    #end
}
