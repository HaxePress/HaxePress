package fixtures;

import hx.press.validation.Flag;
import hx.press.validation.PositiveInt;
import hx.press.validation.Port;
import hx.press.validation.Slug;
import hx.press.validation.TextLine;
import hx.press.validation.Token;

/** What the shared validators answer for edge cases; `tests/validation.py` holds the expected answers. **/
class ValidatorProbe {
    static final numbers = [
        "1",
        "42",
        "2147483647",
        "2147483648",
        "99999999999",
        "0",
        "01",
        "+1",
        " 1",
        "1 ",
        "1\n",
        "0x1F",
        "-1",
        "",
        "١"
    ];
    static final ports = ["1", "80", "65535", "65536", "0", "080", "3306\n"];
    static final slugs = ["my-post", "a", "a1-b2", "My-Post", "a--b", "-a", "a-", "a_b", "a b", "a\n", ""];
    static final tokens = [
        "abcdefghijklmnopqrstuvwxyzAB_-09",
        "abcdefghijklmnopqrstuvwxyzAB_-0",
        "abcdefghijklmnopqrstuvwxyzAB_-090",
        "abcdefghijklmnopqrstuvwxyzAB+/09",
        "abcdefghijklmnopqrstuvwxyzAB_-0\n"
    ];
    static final lines = [
        "Ada Lovelace",
        "",
        "Çağrı Yıldırım",
        "tab\there",
        "line\n",
        "del\x7f",
        "nul\x00"
    ];
    static final flags = ["0", "1", "2", "true", "", " 1"];

    public static function run():Dynamic {
        return {
            positiveInt: [for (text in numbers) {text: text, value: PositiveInt.parse(text)}],
            capped: [PositiveInt.parse("999", 999), PositiveInt.parse("1000", 999)],
            ports: [
                for (text in ports)
                    {
                        text: text,
                        value: Port.parse(text)
                    }
            ],
            slugs: [for (text in slugs) {text: text, valid: Slug.valid(text)}],
            prefixed: [
                Slug.prefixed("theme-simple", "theme-"),
                Slug.prefixed("theme-", "theme-"),
                Slug.prefixed("plugin-simple", "theme-")
            ],
            tokens: [
                for (text in tokens)
                    {
                        text: text,
                        valid: Token.valid(text)
                    }
            ],
            bearer: [
                Token.after("Bearer hxb_abcdefghijklmnopqrstuvwxyzAB_-09", "Bearer hxb_"),
                Token.after("Bearer hxb_abcdefghijklmnopqrstuvwxyzAB_-0", "Bearer hxb_")
            ],
            lines: [
                for (text in lines)
                    {
                        text: text,
                        valid: TextLine.valid(text)
                    }
            ],
            flags: [for (text in flags) {text: text, valid: Flag.valid(text)}],
            nonText: [Flag.valid(1), Flag.valid(true), TextLine.valid(null), Token.valid(null)]
        };
    }
}
