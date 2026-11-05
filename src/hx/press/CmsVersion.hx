package hx.press;

import haxe.Json;
import haxe.Resource;

class CmsVersion {
    static final release:{version:String, pluginApiVersion:Int} = Json.parse(Resource.getString("hx.press.version"));

    public static var version(get, never):String;
    public static var pluginApiVersion(get, never):Int;

    static function get_version():String {
        return release.version;
    }

    static function get_pluginApiVersion():Int {
        return release.pluginApiVersion;
    }
}
