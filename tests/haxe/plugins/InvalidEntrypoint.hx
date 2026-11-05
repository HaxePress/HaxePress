package plugins;

class InvalidEntrypoint {
    public function new() {}

    public function dispatch(event:String, context:String):String {
        return "{}";
    }
}
