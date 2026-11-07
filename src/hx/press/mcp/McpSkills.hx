package hx.press.mcp;

import haxe.Exception;
import haxe.Json;
import haxe.Resource;
import haxe.crypto.Sha256;
import haxe.io.Bytes;
import hx.press.mcp.McpSchema.field;
import hx.press.mcp.McpSchema.object;
import hx.press.mcp.McpServer.McpError;

/**
    Serves the theme design skill to MCP clients. Hosts that support the
    skills extension (SEP-2640) discover it with `skills/list` and read its
    files as `skill://` resources; every client can also reach it through a
    prompt and a read-only tool. The files under `mcp/skills/` are embedded
    in the build, so a client always gets the version that matches the site.
**/
class McpSkills {
    public static inline var EXTENSION = "io.modelcontextprotocol/skills";
    public static inline var NAME = "haxepress-theme-design";
    public static inline var ROOT = 'skill://haxepress-theme-design';
    public static inline var SKILL_URI = 'skill://haxepress-theme-design/SKILL.md';

    /** The skill's files, relative to its folder, in the order clients list them. **/
    public static final files = [
        "SKILL.md",
        "references/document-model.md",
        "references/edit-operations.md",
        "references/rendered-markup.md",
        "references/visual-review.md"
    ];

    /** The instructions line that points every client at the skill. **/
    public static final pointer = 'Before designing, restyling or reviewing a theme, read the theme design skill: the resource ${SKILL_URI}, or the get_theme_design_skill tool when resources are unavailable.';

    static var cachedEntry:Null<Dynamic>;

    public static function source(path:String):String {
        var text = Resource.getString('mcp.skill.${path}');
        if (text == null) {
            throw new Exception('The skill file ${path} is missing from the build.');
        }
        return text;
    }

    /** The `skills/list` entry: the frontmatter and each file's digest and size. **/
    public static function entry():Dynamic {
        if (cachedEntry != null) {
            return cachedEntry;
        }
        var resources = [
            for (path in files) {
                var bytes = Bytes.ofString(source(path));
                {
                    uri: '${ROOT}/${path}',
                    digest: 'sha256:${Sha256.make(bytes).toHex()}',
                    size: bytes.length
                };
            }
        ];
        cachedEntry = {
            uri: SKILL_URI,
            frontmatter: frontmatter(source("SKILL.md")),
            resources: resources
        };
        return cachedEntry;
    }

    /**
        Reads the skill's YAML frontmatter. It accepts the subset the skill
        uses: plain or quoted scalars and one level of nested mappings.
        Anything else is an error instead of frontmatter that differs from
        the file.
    **/
    public static function frontmatter(markdown:String):Dynamic {
        var block = ~/^---\n([\s\S]*?)\n---\n/;
        if (!block.match(markdown)) {
            throw new Exception("The skill needs YAML frontmatter.");
        }
        var result:Dynamic = {};
        var nested:Null<Dynamic> = null;
        var child = ~/^ {2}([a-z][a-z0-9-]*): (.+)$/;
        var parent = ~/^([a-z][a-z0-9-]*):(?: (.+))?$/;
        for (line in block.matched(1).split("\n")) {
            if (nested != null && child.match(line)) {
                Reflect.setField(nested, child.matched(1), scalar(child.matched(2)));
                continue;
            }
            if (!parent.match(line)) {
                throw new Exception('Unsupported frontmatter line: ${line}');
            }
            var value:Null<String> = parent.matched(2);
            if (value == null) {
                nested = {};
                Reflect.setField(result, parent.matched(1), nested);
            } else {
                nested = null;
                Reflect.setField(result, parent.matched(1), scalar(value));
            }
        }
        if (result.name != NAME || !Std.isOfType(result.description, String)) {
            throw new Exception("The skill frontmatter needs its name and a description.");
        }
        return result;
    }

    static function scalar(value:String):String {
        if (StringTools.startsWith(value, '"')) {
            if (!~/^"(?:[^"\\]|\\.)*"$/.match(value)) {
                throw new Exception('Unsupported value: ${value}');
            }
            return Json.parse(value);
        }
        // Prettier writes YAML strings in single quotes, where '' is a quote.
        if (StringTools.startsWith(value, "'")) {
            if (!~/^'(?:[^']|'')*'$/.match(value)) {
                throw new Exception('Unsupported value: ${value}');
            }
            return StringTools.replace(value.substr(1, value.length - 2), "''", "'");
        }
        if (~/^['&*!|>%@`{\[]|: | #/.match(value)) {
            throw new Exception('Unsupported value: ${value}');
        }
        return value;
    }

    public static function register(server:McpServer):Void {
        var skill = entry();
        server.extension(EXTENSION, {});
        server.method("skills/list", params -> {resultType: "complete", skills: [skill]});
        server.method("skills/get", params -> {
            if (params.uri != SKILL_URI) {
                throw new McpError(McpError.INVALID_PARAMS, "Unknown skill");
            }
            return {resultType: "complete", skill: skill};
        });
        var description:String = skill.frontmatter.description;
        for (path in files) {
            var main = path == "SKILL.md";
            var text = source(path);
            server.resource({
                uri: '${ROOT}/${path}',
                name: main ? NAME : '${NAME}/${path}',
                mimeType: "text/markdown",
                description: main ? description : 'Reference for the ${NAME} skill.',
                read: () -> text
            });
        }
        var fileChoice = McpSchema.withDefault(McpSchema.choice(files), "SKILL.md");
        var fileSchema = McpSchema.describe(fileChoice,
            "A file of the skill, relative to its folder.");
        server.tool({
            name: "get_theme_design_skill",
            description: "Read the theme design skill: the workflow, design rules and review checklist for creating or restyling a HaxePress theme. Read SKILL.md first, then a reference file when it points you there.",
            inputSchema: McpSchema.input([McpSchema.optional("file", fileSchema)]),
            annotations: McpTools.readOnly,
            meta: null,
            run: arguments -> {
                content: [{type: "text", text: source(arguments.file)}]
            }
        });
        var brief = McpSchema.describe(McpSchema.string(4000),
            "What the site is about and how it should look and feel.");
        server.prompt({
            name: "design_theme",
            title: "Design a theme",
            description: "Create or restyle a HaxePress theme with the theme design skill.",
            arguments: [
                {
                    name: "brief",
                    description: "What the site is about and how it should look and feel.",
                    required: true
                }
            ],
            argsSchema: object([field("brief", brief)]),
            get: arguments -> {
                var text = '${source("SKILL.md")}\n\n---\n\nFollow the skill above. Its reference files are available as ${ROOT}/references/… resources or through get_theme_design_skill.\n\nThe brief:\n\n${arguments.brief}';
                return {messages: [{role: "user", content: {type: "text", text: text}}]};
            }
        });
    }
}
