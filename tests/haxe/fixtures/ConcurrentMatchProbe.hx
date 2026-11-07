package fixtures;

import haxe.ds.StringMap;
import hx.press.content.Markdown;
import hx.press.view.ThemeStyle;
import sys.thread.Deque;
import sys.thread.Thread;

/**
    Runs theme style and Markdown validation on several threads at once and
    reports each thread's first result that differs from a single thread's.
    Threads alternate between inputs with different results, so a match
    whose state another thread's EReg overwrote changes the result.
**/
class ConcurrentMatchProbe {
    static inline final THREADS = 8;
    static inline final ROUNDS = 400;
    // Variant 0 passes every check and variant 1 fails them; threads only read these.
    static final records:Array<Dynamic> = [
        {green: "#2457a6", contentWidth: "760px", fontBody: "'Inter', sans-serif"},
        {green: "red;x", contentWidth: "1e3", fontBody: "url(x)"}
    ];
    static final declarationNames = ["--paper", "--Paper"];
    static final declarationValues = ["#ffffff", "12px;"];
    static final themeSettings:Array<Dynamic> = [
        {accent: "#2457a6", paper: "#fdfbf7", width: "800"},
        {accent: "blue", paper: "#fdfbf", width: "x"}
    ];
    static final markdownSources = [
        "```\n![a](/a.png)\n```\n\n- ![b](/b.png)\n",
        "# ![c](/c.png)\n\n> ![d](/d.png)\n"
    ];

    public static function run():Array<String> {
        var expected = [for (variant in 0...2) result(variant)];
        var finished = new Deque<String>();
        for (thread in 0...THREADS) {
            Thread.create(() -> {
                var failure = "";
                for (round in 0...ROUNDS) {
                    var variant = (thread + round) % 2;
                    var found = try {
                        result(variant);
                    } catch (error:Dynamic) {
                        'error ${Std.string(error)}';
                    }
                    if (failure == "" && found != expected[variant]) {
                        failure = 'variant ${variant}: ${found}';
                    }
                }
                finished.add(failure);
            });
        }
        var failures = [for (thread in 0...THREADS) finished.pop(true)];
        return failures.filter(failure -> failure != "");
    }

    static function result(variant:Int):String {
        var declarations = new StringMap<String>();
        declarations.set(declarationNames[variant], declarationValues[variant]);
        var variables = ThemeStyle.variables({settings: themeSettings[variant]});
        var variableList = [for (name => value in variables) '${name}=${value}'];
        variableList.sort(Reflect.compare);
        var images = Markdown.imageUrls(markdownSources[variant]);
        var parts = [
            ThemeStyle.fromRecord(records[variant]),
            ThemeStyle.declarations(declarations),
            variableList.join(";"),
            images.join(",")
        ];
        return parts.join(" | ");
    }
}
