package hx.press.plugins;

/** Native host capabilities shared by JVM, CPPIA and PHP modules. */
@:keep
#if jvm
@:nativeGen
#end
interface PluginHost {
    public function admin(routes:Void->Void):Void;
    public function can(capability:String):Bool;

    /** Keeps a recurring task; registering the same task again keeps its next run. **/
    public function schedule(pluginId:String, key:String, intervalSeconds:Int,
        ?payload:String):Void;

    /**
        Creates or replaces a task: its interval, JSON payload, whether it
        runs, and its next run in epoch milliseconds (one interval from now
        when omitted).
    **/
    public function saveSchedule(pluginId:String, key:String, intervalSeconds:Int, payload:String,
        enabled:Bool, ?nextRun:Float):Void;

    /**
        The plugin's tasks, soonest first, as a JSON array of `key`,
        `payload`, `intervalSeconds`, `enabled`, `nextRun`, `lastRun`,
        `lastError` and `running`.
    **/
    public function schedules(pluginId:String, limit:Int):String;

    public function unschedule(pluginId:String, key:String):Bool;
}
