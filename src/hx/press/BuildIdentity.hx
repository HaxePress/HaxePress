package hx.press;

import haxe.macro.Expr;

/**
    Identifies this build of the application. Records that depend on the
    compiled code, such as the migrated schema and stored template images,
    are kept under it, so a new build never reuses them.
**/
class BuildIdentity {
    #if !macro
    public static final id:String = stamp();
    #end

    static macro function stamp():ExprOf<String> {
        var value = '${DateTools.format(Date.now(), "%Y%m%d%H%M%S")}-${Std.random(0x7fffffff)}';
        return macro $v{value};
    }
}
