package hx.press.install;

import haxe.crypto.Base64;
import haxe.crypto.Hmac;
import haxe.crypto.Md5;
import haxe.crypto.random.SecureRandom;
import haxe.io.Bytes;
import hx.well.facades.Environment;
import hx.well.facades.Storage;
import hx.well.http.Request;

/**
    The setup key opens the installer from any connection, such as a
    Cloudflare Tunnel, where the visitor's address cannot be trusted. A
    site that is not installed creates it like HxWell creates `APP_KEY`, 32
    random bytes in Base64, saves it in .env as `INSTALL_KEY` and prints it
    when it starts; installation removes it. Entering the key sets a cookie
    that only this key and `APP_KEY` can produce.
**/
class InstallationKey {
    public static inline var SETTING = "INSTALL_KEY";
    public static inline var COOKIE = "haxepress_install";

    /** Wrong keys a connection may try within `WINDOW_SECONDS`. **/
    static inline var MAX_ATTEMPTS = 10;

    static inline var WINDOW_SECONDS = 60.0;

    public static function configured():String {
        return StringTools.trim(Environment.env(SETTING, ""));
    }

    /**
        Creates the setup key of a site that is not installed when .env has
        none, and prints it for whoever starts the site. PHP prints nothing:
        `php setup.php` shows the key it writes.
    **/
    public static function ensure():Void {
        var key = configured();
        if (key == "") {
            key = Base64.encode(SecureRandom.bytes(32));
            InstallationEnv.update([SETTING => key]);
            Environment.set(SETTING, key);
        }
        #if !php
        Sys.println("");
        Sys.println("HaxePress is not installed yet. Open /admin/install and enter this setup key:");
        Sys.println('  ${key}');
        Sys.println("It is saved in .env as INSTALL_KEY and is removed when installation finishes.");
        Sys.println("");
        #end
    }

    /** Whether `input` is the setup key, compared in constant time. **/
    public static function matches(input:String):Bool {
        var key = configured();
        return key != "" && same(StringTools.trim(input), key);
    }

    /** The cookie value that proves the key was entered. **/
    public static function token():String {
        var secret = Bytes.ofString(Environment.env("APP_KEY", ""));
        var message = Bytes.ofString('haxepress-install\n${configured()}');
        return new Hmac(SHA256).make(secret, message).toHex();
    }

    /** Whether the request carries the cookie of the current setup key. **/
    public static function unlocked(request:Request):Bool {
        if (configured() == "") {
            return false;
        }
        var cookie = request.cookie(COOKIE, "");
        return cookie != "" && same(cookie, token());
    }

    /** Compares two values without stopping at the first difference. **/
    static function same(left:String, right:String):Bool {
        var a = Bytes.ofString(left);
        var b = Bytes.ofString(right);
        if (a.length != b.length || b.length == 0) {
            return false;
        }
        var difference = 0;
        for (index in 0...a.length) {
            difference |= a.get(index) ^ b.get(index);
        }
        return difference == 0;
    }

    /**
        Counts a wrong key of a connection and tells whether it may try
        again. The key's 256 random bits make guessing hopeless; the limit
        keeps the installer from serving as a target.
    **/
    public static function allowAttempt(request:Request):Bool {
        var disk = Storage.disk("local");
        var path = 'cache/install-attempts/${Md5.encode(request.ip ?? "")}';
        var now = Sys.time();
        var count = 0;
        var started = now;
        if (disk.fileExists(path)) {
            var parts = disk.get(path).split(":");
            var stored = Std.parseFloat(parts[1] ?? "");
            if (parts.length == 2 && Math.isFinite(stored) && now - stored < WINDOW_SECONDS) {
                count = Std.parseInt(parts[0]) ?? 0;
                started = stored;
            }
        }
        if (count >= MAX_ATTEMPTS) {
            return false;
        }
        disk.put(path, '${count + 1}:${started}', "private");
        return true;
    }
}
