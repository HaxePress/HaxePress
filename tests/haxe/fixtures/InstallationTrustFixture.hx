package fixtures;

import haxe.Exception;
import hx.press.install.InstallationState;
import hx.well.facades.Environment;
import java.NativeArray;

@:keep
@:nativeGen
class InstallationTrustFixture {
    static function verify(allowed:Array<String>, denied:Array<String>):Void {
        for (address in allowed) {
            if (!InstallationState.trusted(address)) {
                throw new Exception("Installation rejected an allowed peer: " + address);
            }
        }
        for (address in denied) {
            if (InstallationState.trusted(address)) {
                throw new Exception("Installation trusted a disallowed peer: " + address);
            }
        }
    }

    public static function main(arguments:NativeArray<String>):Void {
        Environment.load(".env");
        if (Environment.env("APP_NAME") != "haxepress_test") {
            throw new Exception("Installation trust checks require an isolated test environment.");
        }
        var loopback = ["127.0.0.1", "::ffff:127.0.0.1"];
        var otherPeers = ["127.0.0.2", "::1", "192.0.2.11", "2001:db8::1"];
        verify(loopback, otherPeers);
        for (configuration in ["", "deadbeef", "localhost", "*"]) {
            Environment.set("INSTALL_TRUSTED_IPS", configuration);
            verify(loopback, otherPeers);
        }
        Environment.set("INSTALL_TRUSTED_IPS", "192.0.2.11");
        verify(["127.0.0.1", "192.0.2.11"], ["127.0.0.2", "192.0.2.12", "::1"]);
        Environment.set("INSTALL_TRUSTED_IPS", "127.0.0.2,::1,2001:db8::1");
        verify(["127.0.0.1", "127.0.0.2", "::1", "2001:0db8:0:0:0:0:0:1"], ["192.0.2.11"]);
        Sys.println("PASS Installation trust: automatic 127.0.0.1, exact exception boundary, explicit IPv4/IPv6 entries and invalid configuration");
    }
}
