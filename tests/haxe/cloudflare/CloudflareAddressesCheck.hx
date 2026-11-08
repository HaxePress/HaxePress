import extensions.cloudflare.CloudflareAddresses;
import extensions.cloudflare.CloudflareCountry;

/** Checks the Cloudflare plugin's address parsing, ranges and countries; run with `--interp`. **/
class CloudflareAddressesCheck {
    static var failures:Array<String> = [];

    static function main():Void {
        var parsed:Array<{text:String, groups:Null<Array<Int>>}> = [
            {text: "203.0.113.7", groups: [0, 0, 0, 0, 0, 0xffff, 0xcb00, 0x7107]},
            {text: "0.0.0.0", groups: [0, 0, 0, 0, 0, 0xffff, 0, 0]},
            {text: "255.255.255.255", groups: [0, 0, 0, 0, 0, 0xffff, 0xffff, 0xffff]},
            {text: "::", groups: [0, 0, 0, 0, 0, 0, 0, 0]},
            {text: "::1", groups: [0, 0, 0, 0, 0, 0, 0, 1]},
            {text: "1::", groups: [1, 0, 0, 0, 0, 0, 0, 0]},
            {text: "2001:db8::7", groups: [0x2001, 0xdb8, 0, 0, 0, 0, 0, 7]},
            {
                text: "2001:0DB8:0000:0000:0000:0000:0000:0007",
                groups: [0x2001, 0xdb8, 0, 0, 0, 0, 0, 7]
            },
            {text: "0:0:0:0:0:0:0:1", groups: [0, 0, 0, 0, 0, 0, 0, 1]},
            {text: "1:2:3:4:5:6:7::", groups: [1, 2, 3, 4, 5, 6, 7, 0]},
            {text: "::2:3:4:5:6:7:8", groups: [0, 2, 3, 4, 5, 6, 7, 8]},
            {text: "1:2::7:8", groups: [1, 2, 0, 0, 0, 0, 7, 8]},
            {text: "::ffff:192.0.2.1", groups: [0, 0, 0, 0, 0, 0xffff, 0xc000, 0x0201]},
            {text: "0:0:0:0:0:ffff:192.0.2.1", groups: [0, 0, 0, 0, 0, 0xffff, 0xc000, 0x0201]},
            {text: "", groups: null},
            {text: "1.2.3", groups: null},
            {text: "1.2.3.4.5", groups: null},
            {text: "256.1.1.1", groups: null},
            {text: "01.2.3.4", groups: null},
            {text: "1..3.4", groups: null},
            {text: " 1.2.3.4", groups: null},
            {text: "1.2.3.4\n", groups: null},
            {text: "198.51.100.10, 203.0.113.1", groups: null},
            {text: "1:2:3:4:5:6:7", groups: null},
            {text: "1:2:3:4:5:6:7:8:9", groups: null},
            {text: "1:2:3:4:5:6:7:8::", groups: null},
            {text: "1::2::3", groups: null},
            {text: ":::1", groups: null},
            {text: ":1::", groups: null},
            {text: "::1:", groups: null},
            {text: "12345::", groups: null},
            {text: "g::", groups: null},
            {text: "1.2.3.4::", groups: null},
            {text: "::1.2.3.4:5", groups: null},
            {text: "1:2:3:4:5:6:7:1.2.3.4", groups: null},
            {text: "fe80::1%en0", groups: null},
            {text: "[::1]", groups: null},
            {text: "localhost", groups: null}
        ];
        for (item in parsed) {
            var actual = CloudflareAddresses.parse(item.text);
            var expected = item.groups;
            var same = actual == null ? expected == null : expected != null
                && actual.join(",") == expected.join(",");
            check(same, 'parse("${item.text}") returned ${Std.string(actual)}');
        }
        var peers:Array<{peer:Null<String>, tunnel:Bool, expected:Bool}> = [
            {peer: "173.245.48.1", tunnel: false, expected: true},
            {peer: "173.245.63.255", tunnel: false, expected: true},
            {peer: "173.245.64.0", tunnel: false, expected: false},
            {peer: "104.15.255.255", tunnel: false, expected: false},
            {peer: "104.23.255.255", tunnel: false, expected: true},
            {peer: "104.27.255.255", tunnel: false, expected: true},
            {peer: "104.28.0.0", tunnel: false, expected: false},
            {peer: "::ffff:104.16.0.1", tunnel: false, expected: true},
            {peer: "2400:cb00::1", tunnel: false, expected: true},
            {peer: "2400:cb01::1", tunnel: false, expected: false},
            {peer: "2a06:98c7:ffff::1", tunnel: false, expected: true},
            {peer: "2a06:98c8::1", tunnel: false, expected: false},
            {peer: "198.51.100.10", tunnel: false, expected: false},
            {peer: "198.51.100.10", tunnel: true, expected: false},
            {peer: "127.0.0.1", tunnel: false, expected: false},
            {peer: "127.0.0.1", tunnel: true, expected: true},
            {peer: "127.1.2.3", tunnel: true, expected: true},
            {peer: "::ffff:127.0.0.1", tunnel: true, expected: true},
            {peer: "::1", tunnel: false, expected: false},
            {peer: "::1", tunnel: true, expected: true},
            {peer: "0:0:0:0:0:0:0:1", tunnel: true, expected: true},
            {peer: "::2", tunnel: true, expected: false},
            {peer: "fe80::1%en0", tunnel: true, expected: false},
            {peer: "2606:4700::6810:84e5%en0", tunnel: false, expected: true},
            {peer: "", tunnel: true, expected: false},
            {peer: null, tunnel: true, expected: false}
        ];
        for (item in peers) {
            var actual = CloudflareAddresses.fromCloudflare(item.peer, item.tunnel);
            check(actual == item.expected,
                'fromCloudflare("${item.peer}", ${item.tunnel}) returned ${actual}');
        }
        var countries:Array<{text:Null<String>, expected:Null<String>}> = [
            {text: "TR", expected: "TR"},
            {text: "de", expected: "DE"},
            {text: " US ", expected: "US"},
            {text: "XX", expected: null},
            {text: "xx", expected: null},
            {text: "T1", expected: null},
            {text: "", expected: null},
            {text: "T", expected: null},
            {text: "TUR", expected: null},
            {text: "1A", expected: null},
            {text: "Ü1", expected: null},
            {text: "TR\nDE", expected: null},
            {text: null, expected: null}
        ];
        for (item in countries) {
            var actual = CloudflareCountry.normalize(item.text);
            check(actual == item.expected,
                'CloudflareCountry.normalize("${item.text}") returned ${actual}');
        }
        if (failures.length > 0) {
            for (failure in failures) {
                Sys.println('FAIL ${failure}');
            }
            Sys.exit(1);
        }
        var total = parsed.length + peers.length + countries.length;
        Sys.println('PASS ${total} Cloudflare address and country checks');
    }

    static function check(condition:Bool, label:String):Void {
        if (!condition) {
            failures.push(label);
        }
    }
}
