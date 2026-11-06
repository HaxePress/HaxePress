package hx.press.plugins;

/** Native host capabilities shared by JVM, CPPIA and PHP modules. */
@:keep
#if jvm
@:nativeGen
#end
interface PluginHost {
    public function admin(routes:Void->Void):Void;
    public function can(capability:String):Bool;
    public function schedule(pluginId:String, key:String, intervalSeconds:Int,
        ?payload:String):Void;
    public function unschedule(pluginId:String, key:String):Bool;
}
