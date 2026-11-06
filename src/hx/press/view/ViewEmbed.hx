package hx.press.view;

#if macro
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import haxe.macro.Context;
import haxe.macro.Expr;
#end

/** Compile-time embedding of templates and the client runtime; no runtime code lives here. */
class ViewEmbed {
    /** Embeds every `.well.html` file under `resources/views` and returns the template names. **/
    public static macro function templates():ExprOf<Array<String>> {
        var names:Array<String> = [];
        collect("resources/views", "", names);
        names.sort(Reflect.compare);
        return macro $v{names};
    }

    /** Embeds `client/wellout.js` of the wellout library as the `wellout.client` resource. **/
    public static macro function client():Expr {
        var marker = Context.resolvePath("wellout/ByteWriter.hx");
        var root = Path.directory(Path.directory(Path.directory(marker)));
        var path = Path.join([root, "client", "wellout.js"]);
        if (!FileSystem.exists(path)) {
            Context.error('The Wellout client runtime is missing: ${path}', Context.currentPos());
        }
        Context.addResource("wellout.client", File.getBytes(path));
        Context.registerModuleDependency("hx.press.view.WelloutClient", path);
        return macro null;
    }

    #if macro
    static function collect(directory:String, relative:String, names:Array<String>):Void {
        if (!FileSystem.exists(directory)) {
            return;
        }
        for (entry in FileSystem.readDirectory(directory)) {
            var path = '${directory}/${entry}';
            var child = relative == "" ? entry : '${relative}/${entry}';
            if (FileSystem.isDirectory(path)) {
                collect(path, child, names);
                continue;
            }
            if (!StringTools.endsWith(entry, ".well.html")) {
                continue;
            }
            var base = child.substr(0, child.length - ".well.html".length);
            var name = templateName(base);
            Context.addResource('well:${name}', File.getBytes(path));
            Context.registerModuleDependency("hx.press.view.ViewSources", path);
            names.push(name);
        }
    }

    static function templateName(relative:String):String {
        for (prefix in ["components/", "layouts/"]) {
            if (StringTools.startsWith(relative, prefix)) {
                var parts = relative.split("/");
                return parts[parts.length - 1];
            }
        }
        if (StringTools.startsWith(relative, "pages/")) {
            return relative.substr("pages/".length);
        }
        return relative;
    }
    #end
}
