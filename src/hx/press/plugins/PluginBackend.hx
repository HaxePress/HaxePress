package hx.press.plugins;

interface PluginBackend {
    public function create(host:PluginHost, context:String):Void;
    public function destroy():Void;
    public function dispatch(event:String, context:String):String;
    public function close():Void;
}
