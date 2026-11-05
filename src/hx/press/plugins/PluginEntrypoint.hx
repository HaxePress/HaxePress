package hx.press.plugins;

/** Shared JVM, CPPIA and PHP contract. Context and results are JSON objects. */
@:keep
#if jvm
@:nativeGen
#end
interface PluginEntrypoint {
    public function onCreate(host:PluginHost, context:String):Void;
    public function onDestroy():Void;
    public function dispatch(event:String, context:String):String;
}
