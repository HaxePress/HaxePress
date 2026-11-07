package hx.press;

import hx.press.validation.Port;
import hx.well.facades.Environment;

class ServerSettings {
    public static var host(get, never):String;
    public static var port(get, never):Int;
    public static var connections(get, never):Int;
    public static var workers(get, never):Int;
    public static var contentCacheTtl(get, never):Int;

    static function get_host():String
        return Environment.env("HOST", "127.0.0.1");

    static function get_port():Int
        return Port.setting("PORT", Environment.env("PORT", "3000"));

    static function get_connections():Int
        return positiveInt("MAX_CONNECTIONS", #if jvm 10000 #else 1000 #end, 100000);

    static function get_workers():Int
        return positiveInt("WORKERS", #if jvm 16 #else 4 #end, 256);

    static function get_contentCacheTtl():Int
        return positiveInt("CONTENT_CACHE_TTL", 600, 86400);

    static function positiveInt(key:String, fallback:Int, max:Int):Int {
        var value = Std.parseInt(Environment.env(key, Std.string(fallback)));
        if (value == null || value < 1 || value > max)
            throw '${key} must be between 1 and ${max}.';
        return value;
    }
}
