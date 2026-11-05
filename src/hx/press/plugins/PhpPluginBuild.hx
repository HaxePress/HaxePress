package hx.press.plugins;

#if macro
import haxe.macro.Context;
import haxe.macro.Type.BaseType;

/** Give package-owned types build-specific names while retaining the shared host API. */
class PhpPluginBuild {
    public static function configure(namespace:String, prefix:String):Void {
        Context.onAfterTyping(types -> {
            for (type in types) {
                var base:BaseType = switch (type) {
                    case TClassDecl(reference): reference.get();
                    case TEnumDecl(reference): reference.get();
                    default: continue;
                };
                var name = base.pack.concat([base.name]).join(".");
                if (name != namespace && !StringTools.startsWith(name, namespace + ".")) {
                    continue;
                }
                if (base.meta.has(":native")) {
                    Context.error("PHP plugin types cannot override their native namespace.",
                        base.pos);
                }
                var nativeName = prefix + "." + name;
                base.meta.add(":native", [macro $v{nativeName}], base.pos);
            }
        });
    }
}
#end
