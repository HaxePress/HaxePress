package extensions.cloudflare;

import haxe.Exception;

/** An address range: the first `prefix` bits of eight 16-bit groups. **/
private class AddressRange {
    public final groups:Array<Int>;
    public final prefix:Int;

    public function new(groups:Array<Int>, prefix:Int) {
        this.groups = groups;
        this.prefix = prefix;
    }

    public function contains(address:Array<Int>):Bool {
        var remaining = prefix;
        var index = 0;
        while (remaining >= 16) {
            if (address[index] != groups[index]) {
                return false;
            }
            index++;
            remaining -= 16;
        }
        if (remaining == 0) {
            return true;
        }
        var mask = (0xffff << (16 - remaining)) & 0xffff;
        return (address[index] & mask) == (groups[index] & mask);
    }
}

/**
    IP addresses as eight 16-bit groups, with IPv4 addresses mapped into
    IPv6 (`::ffff:a.b.c.d`), and the addresses Cloudflare connects from.
**/
class CloudflareAddresses {
    /** Cloudflare's published edge ranges, https://www.cloudflare.com/ips/. **/
    static final edges = ranges([
        "173.245.48.0/20",
        "103.21.244.0/22",
        "103.22.200.0/22",
        "103.31.4.0/22",
        "141.101.64.0/18",
        "108.162.192.0/18",
        "190.93.240.0/20",
        "188.114.96.0/20",
        "197.234.240.0/22",
        "198.41.128.0/17",
        "162.158.0.0/15",
        "104.16.0.0/13",
        "104.24.0.0/14",
        "172.64.0.0/13",
        "131.0.72.0/22",
        "2400:cb00::/32",
        "2606:4700::/32",
        "2803:f800::/32",
        "2405:b500::/32",
        "2405:8100::/32",
        "2a06:98c0::/29",
        "2c0f:f248::/32"
    ]);

    /** The addresses Cloudflare Tunnel's connector uses on the site's own server. **/
    static final loopback = ranges(["127.0.0.0/8", "::1/128"]);

    /**
        Whether a connection from `peer` comes from Cloudflare: from its edge,
        or, with `tunnel`, from the tunnel connector on this server.
    **/
    public static function fromCloudflare(peer:Null<String>, tunnel:Bool):Bool {
        if (peer == null) {
            return false;
        }
        // Link-local peers carry their interface after the address.
        var zone = peer.indexOf("%");
        var address = parse(zone < 0 ? peer : peer.substr(0, zone));
        if (address == null) {
            return false;
        }
        return within(edges, address) || (tunnel && within(loopback, address));
    }

    /** The eight 16-bit groups of an IP address, or `null` when `text` is not one. **/
    public static function parse(text:Null<String>):Null<Array<Int>> {
        if (text == null || text.length == 0 || text.length > 45) {
            return null;
        }
        var groups = [0, 0, 0, 0, 0, 0, 0, 0];
        var end = text.length;
        if (text.indexOf(":") < 0) {
            groups[5] = 0xffff;
            return ipv4(text, 0, end, groups, 6) ? groups : null;
        }
        var gap = text.indexOf("::");
        if (gap < 0) {
            return hextets(text, 0, end, groups, 0, 8, true) == 8 ? groups : null;
        }
        if (text.indexOf("::", gap + 1) >= 0) {
            return null;
        }
        var head = hextets(text, 0, gap, groups, 0, 7, false);
        if (head < 0) {
            return null;
        }
        var tail = hextets(text, gap + 2, end, groups, head, 7 - head, true);
        if (tail < 0) {
            return null;
        }
        // The tail moves to the end, and the groups the gap stands for are zero.
        var first = 8 - tail;
        var index = tail;
        while (index > 0) {
            index--;
            groups[first + index] = groups[head + index];
        }
        for (zero in head...first) {
            groups[zero] = 0;
        }
        return groups;
    }

    static function within(list:Array<AddressRange>, address:Array<Int>):Bool {
        for (range in list) {
            if (range.contains(address)) {
                return true;
            }
        }
        return false;
    }

    static function ranges(texts:Array<String>):Array<AddressRange> {
        var list:Array<AddressRange> = [];
        for (text in texts) {
            var slash = text.indexOf("/");
            if (slash < 0) {
                throw new Exception('The address range ${text} has no prefix length.');
            }
            var groups = parse(text.substr(0, slash));
            var bits = Std.parseInt(text.substr(slash + 1));
            if (groups == null || bits == null) {
                throw new Exception('The address range ${text} is not valid.');
            }
            var prefix = text.indexOf(":") < 0 ? 96 + bits : bits;
            list.push(new AddressRange(groups, prefix));
        }
        return list;
    }

    /**
        Reads the colon-separated groups between `start` and `end` into
        `groups` from `at`, at most `limit` of them. A dotted IPv4 address
        may end the `last` part. Returns the number of groups, or -1.
    **/
    static function hextets(text:String, start:Int, end:Int, groups:Array<Int>, at:Int, limit:Int,
            last:Bool):Int {
        var count = 0;
        var position = start;
        if (position == end) {
            return 0;
        }
        while (position < end) {
            var separator = position;
            var dotted = false;
            while (separator < end && StringTools.fastCodeAt(text, separator) != ":".code) {
                if (StringTools.fastCodeAt(text, separator) == ".".code) {
                    dotted = true;
                }
                separator++;
            }
            if (dotted) {
                if (!last || separator != end || count + 2 > limit) {
                    return -1;
                }
                return ipv4(text, position, end, groups, at + count) ? count + 2 : -1;
            }
            var length = separator - position;
            if (length == 0 || length > 4 || count == limit) {
                return -1;
            }
            var value = 0;
            for (index in position...separator) {
                var digit = hexDigit(StringTools.fastCodeAt(text, index));
                if (digit < 0) {
                    return -1;
                }
                value = value * 16 + digit;
            }
            groups[at + count] = value;
            count++;
            if (separator == end) {
                return count;
            }
            position = separator + 1;
        }
        // A colon ended the part.
        return -1;
    }

    /** Reads a dotted IPv4 address into the two groups at `at`. **/
    static function ipv4(text:String, start:Int, end:Int, groups:Array<Int>, at:Int):Bool {
        var octets = 0;
        var value = 0;
        var digits = 0;
        var high = 0;
        for (index in start...end) {
            var code = StringTools.fastCodeAt(text, index);
            if (code == ".".code) {
                if (digits == 0 || octets == 3) {
                    return false;
                }
                if (octets % 2 == 0) {
                    high = value;
                } else {
                    groups[at] = (high << 8) | value;
                }
                octets++;
                value = 0;
                digits = 0;
            } else if (code >= "0".code && code <= "9".code) {
                // Leading zeros are rejected: some parsers read them as octal.
                if (digits == 1 && value == 0) {
                    return false;
                }
                value = value * 10 + (code - "0".code);
                digits++;
                if (value > 255) {
                    return false;
                }
            } else {
                return false;
            }
        }
        if (digits == 0 || octets != 3) {
            return false;
        }
        groups[at + 1] = (high << 8) | value;
        return true;
    }

    static function hexDigit(code:Int):Int {
        if (code >= "0".code && code <= "9".code) {
            return code - "0".code;
        }
        if (code >= "a".code && code <= "f".code) {
            return code - "a".code + 10;
        }
        if (code >= "A".code && code <= "F".code) {
            return code - "A".code + 10;
        }
        return -1;
    }
}
