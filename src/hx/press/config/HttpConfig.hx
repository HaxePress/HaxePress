package hx.press.config;

import hx.well.config.IConfig;
import hx.well.facades.Environment;

using Std;

class HttpConfig implements IConfig {
    public function new() {}

    public var max_path_length:Int = Environment.env("MAX_PATH_LENGTH", "1024").parseInt();
    public var max_buffer:Int = Environment.env("MAX_BUFFER", "8192").parseInt();
    public var max_content_length:Int = Environment.env("MAX_CONTENT_LENGTH", "67108864")
        .parseInt();

    public var public_path:String = Environment.env("PUBLIC_PATH", "public");

    public var cache_path:String = Environment.env("CACHE_PATH", "storage/cache");
}
