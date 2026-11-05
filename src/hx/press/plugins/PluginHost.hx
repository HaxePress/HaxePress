package hx.press.plugins;

/** Native host capabilities shared by JVM, CPPIA and PHP modules. */
@:keep
#if jvm
@:nativeGen
#end
interface PluginHost {
    public function admin(routes:Void->Void):Void;
    public function can(capability:String):Bool;
}
