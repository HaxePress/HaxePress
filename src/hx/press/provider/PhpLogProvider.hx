package hx.press.provider;

#if php
import haxe.Log;
import haxe.PosInfos;
import hx.well.provider.AbstractProvider;
import php.Global;

/**
    HxWell silences `trace` on PHP, which hides server errors. This sends
    them to PHP's error log, which the web server or PHP-FPM keeps.
**/
class PhpLogProvider extends AbstractProvider {
    public function boot():Void {
        Log.trace = (value:Dynamic, ?infos:PosInfos) -> {
            // PHP starts the server for each request; its route listing would repeat every time.
            if (infos != null && infos.className == "hx.well.route.Route"
                && infos.methodName == "log") {
                return;
            }
            Global.error_log(Log.formatOutput(value, infos));
        };
    }
}
#end
