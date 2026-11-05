package hx.press.plugins;

/** Keep applied names stable and append migrations when a plugin's schema changes. */
class PluginMigration {
    public final name:String;
    public final up:Void->Void;
    public final transactional:Bool;

    public function new(name:String, up:Void->Void, transactional:Bool = false) {
        this.name = name;
        this.up = up;
        this.transactional = transactional;
    }
}
