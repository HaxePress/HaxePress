package hx.press.ai;

import haxe.Json;
import hx.press.mcp.McpSchema;
import hx.press.mcp.McpSchema.McpField;
import hx.press.mcp.McpSchema.field;
import hx.press.mcp.McpSchema.optional;
import hx.press.mcp.McpServer;
import hx.press.mcp.McpTools;

/**
    Translation tools of the admin MCP catalog. They read and change the
    same texts as the Translations page, through its routes: what the CMS,
    themes, plugins and the site show in each site language, the
    translations they ship and the ones made on this site, which win.
**/
class AdminMcpTranslationTools {
    final server:McpServer;
    final bridge:AdminMcpBridge;
    final canRescan:Bool;

    public static final instruction = "For translations, read get_translation_progress, list_translations with status missing for one language and source, then save a page with save_translations. Keep every {placeholder} of the source text; plural texts take one and other forms. remove_translation brings back the translation a theme or plugin ships.";

    public function new(server:McpServer, bridge:AdminMcpBridge, canRescan:Bool) {
        this.server = server;
        this.bridge = bridge;
        this.canRescan = canRescan;
    }

    static function language():Dynamic {
        return McpSchema.describe(McpSchema.string(35, 2, "^[a-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$"),
            "A site language code from list_languages, such as de or pt-BR.");
    }

    static function source():Dynamic {
        return McpSchema.describe(McpSchema.string(80, null,
            "^(?:core|site|themes|plugins|(?:plugin|theme)-[a-z0-9]+(?:-[a-z0-9]+)*)$"),
            "core for HaxePress, site for the site's own texts, themes or plugins for every package of that kind, or one package id from list_translation_sources.");
    }

    static function single():Dynamic {
        return McpSchema.describe(McpSchema.string(80, null,
            "^(?:core|site|(?:plugin|theme)-[a-z0-9]+(?:-[a-z0-9]+)*)$"),
            "core, site or one package id from list_translation_sources.");
    }

    static function id():Dynamic {
        return McpSchema.integer(1, McpSchema.MAX_INT);
    }

    static function text():Dynamic {
        return McpSchema.string(4000);
    }

    function add(name:String, description:String, fields:Array<McpField>, isReadOnly:Bool,
            run:Dynamic->Dynamic):Void {
        McpTools.add(server, name, description, fields, isReadOnly, run);
    }

    function call(path:String, method:String = "GET", ?data:Dynamic):Dynamic {
        return AdminMcpBridge.result(bridge.request(path, method, data));
    }

    static function query(path:String, values:Array<{name:String, value:Dynamic}>):String {
        var pairs:Array<String> = [];
        for (entry in values) {
            if (entry.value == null || entry.value == "") {
                continue;
            }
            var text = Std.isOfType(entry.value,
                Bool) ? (entry.value ? "all" : "") : Std.string(entry.value);
            if (text != "") {
                pairs.push('${entry.name}=${StringTools.urlEncode(text)}');
            }
        }
        return pairs.length == 0 ? path : '${path}?${pairs.join("&")}';
    }

    /** One translation as the save routes take it. **/
    static function input(entry:Dynamic):Dynamic {
        var data:Dynamic = {};
        if (entry.value != null) {
            data.value = entry.value;
        }
        if (entry.one != null) {
            data.one = entry.one;
        }
        if (entry.other != null) {
            data.other = entry.other;
        }
        return data;
    }

    public function register():Void {
        add("list_translation_sources",
            "List the sources of texts: HaxePress itself, the site's own texts and every installed theme and plugin.",
            [], true, _ -> call("/admin/translations/sources"));
        add("get_translation_progress",
            "Count each site language's texts, how many it translates, how many the site changed and how many need review.",
            [
                optional("source", source()),
                optional("includeAdmin",
                    McpSchema.describe(McpSchema.boolean(),
                        "Also count the administration's texts, which visitors never see."))
            ], true, arguments -> {
                return call(query("/admin/translations/progress", [
                    {name: "source", value: arguments.source},
                    {name: "audience", value: arguments.includeAdmin == true ? "all" : ""}
                ]));
            });
        add("list_translations",
            "List texts with their source wording, placeholders and what a language shows. status missing lists texts without a translation; edited lists the site's own translations. Pages hold 50 texts; pass nextCursor back as cursor.",
            [
                optional("language", language()),
                optional("source", source()),
                optional("status",
                    McpSchema.choice(["all", "missing", "translated", "edited", "review", "unused"])),
                optional("q", McpSchema.string(80)),
                optional("includeAdmin", McpSchema.boolean()),
                optional("cursor", McpSchema.string(1000))
            ], true, arguments -> {
                return call(query("/admin/translations", [
                    {name: "language", value: arguments.language},
                    {name: "source", value: arguments.source},
                    {name: "status", value: arguments.status},
                    {name: "q", value: arguments.q},
                    {name: "audience", value: arguments.includeAdmin == true ? "all" : ""},
                    {name: "cursor", value: arguments.cursor}
                ]));
            });
        add("get_translation", "Read one text with its translation in every site language.",
            [field("id", id())], true, arguments -> {
                var text:Int = arguments.id;
                return call('/admin/translations/${text}');
            });
        add("save_translation",
            "Save the site's translation of one text into a language. It replaces the translation the theme or plugin ships. Plural texts take one and other instead of value.",
            [
                field("id", id()),
                field("language", language()),
                optional("value", text()),
                optional("one", text()),
                optional("other", text())
            ], false, arguments -> {
                var data:Dynamic = input(arguments);
                var text:Int = arguments.id;
                data.text_id = '${text}';
                data.language = arguments.language;
                return call("/admin/translations/save", "POST", data);
            });
        add("save_translations",
            "Save up to 100 translations into one language at once. Valid items are saved; each invalid one is reported.",
            [
                field("language", language()),
                field("items", McpSchema.array(McpSchema.object([
                    field("id", id()),
                    optional("value", text()),
                    optional("one", text()),
                    optional("other", text())
                ]), 1, 100))
            ], false, arguments -> {
                var entries:Array<Dynamic> = arguments.items;
                var items = [
                    for (entry in entries) {
                        var data:Dynamic = input(entry);
                        data.id = entry.id;
                        data;
                    }
                ];
                return call("/admin/translations/save-batch", "POST", {
                    language: arguments.language,
                    items: Json.stringify(items)
                });
            });
        add("remove_translation",
            "Remove the site's translation of a text in one language. The translation the theme or plugin ships applies again, or the source wording when it ships none.",
            [field("id", id()), field("language", language())], false, arguments -> {
                var text:Int = arguments.id;
                return call("/admin/translations/remove", "POST", {
                    text_id: '${text}',
                    language: arguments.language
                });
            });
        add("export_translations",
            "Export the texts of one source in one language as a catalogue of key to text: effective is what the language shows, site the site's own translations, missing the source texts that still need a translation. Pages hold 500 texts; pass nextCursor back as cursor.",
            [
                field("source", single()),
                field("language", language()),
                optional("include", McpSchema.choice(["effective", "site", "missing"])),
                optional("cursor", McpSchema.string(20))
            ], true, arguments -> {
                return call(query("/admin/translations/export", [
                    {name: "source", value: arguments.source},
                    {name: "language", value: arguments.language},
                    {name: "include", value: arguments.include},
                    {name: "cursor", value: arguments.cursor}
                ]));
            });
        add("import_translations",
            "Import a catalogue of key to text (or {one, other}) into one language of one source. mode missing fills only texts without a translation; overwrite replaces the site's translations of the listed keys.",
            [
                field("source", single()),
                field("language", language()),
                field("messages", McpSchema.record()),
                optional("mode", McpSchema.choice(["missing", "overwrite"]))
            ], false, arguments -> {
                return call("/admin/translations/import", "POST", {
                    source: arguments.source,
                    language: arguments.language,
                    mode: arguments.mode ?? "missing",
                    catalogue: Json.stringify(arguments.messages)
                });
            });
        if (canRescan) {
            add("rescan_translations",
                "List the texts of HaxePress and every installed theme and plugin again, after files changed outside the administration.",
                [], false, _ -> call("/admin/translations/rescan", "POST", {}));
        }
    }
}
