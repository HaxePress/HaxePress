package hx.press.config;

import hx.well.config.IConfig;
import hx.press.model.Admin;
import haxe.ds.StringMap;
import hx.well.auth.IAuthenticatable;
import hx.well.facades.Environment;

using Std;

class SessionConfig implements IConfig {
    public function new() {}

    public var path:String = Environment.env("SESSION_PATH", "private/storage/sessions");
    public var lifetime:Int = Environment.env("SESSION_LIFETIME", "120").parseInt();

    public var guards:StringMap<Class<IAuthenticatable>> = ["admin" => Admin];
}
