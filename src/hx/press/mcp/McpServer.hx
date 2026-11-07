package hx.press.mcp;

import haxe.Exception;
import haxe.Json;
import hx.press.mcp.McpSchema.McpSchemaError;

/** A tool result: `content` items, optional `structuredContent` and `isError`. **/
typedef McpToolHandler = Dynamic->Dynamic;

typedef McpTool = {
    var name:String;
    var description:String;
    var inputSchema:Dynamic;
    var annotations:Dynamic;
    var meta:Null<Dynamic>;
    var run:McpToolHandler;
}

typedef McpResource = {
    var uri:String;
    var name:String;
    var mimeType:String;
    var description:String;
    var read:Void->String;
}

typedef McpPromptArgument = {
    var name:String;
    var description:String;
    var required:Bool;
}

typedef McpPrompt = {
    var name:String;
    var title:String;
    var description:String;
    var arguments:Array<McpPromptArgument>;
    var argsSchema:Dynamic;
    var get:Dynamic->Dynamic;
}

/** A JSON-RPC error, with the HTTP status the Streamable HTTP transport answers it with. **/
class McpError extends Exception {
    public static inline var PARSE_ERROR = -32700;
    public static inline var INVALID_REQUEST = -32600;
    public static inline var METHOD_NOT_FOUND = -32601;
    public static inline var INVALID_PARAMS = -32602;
    public static inline var INTERNAL_ERROR = -32603;
    public static inline var HEADER_MISMATCH = -32020;
    public static inline var UNSUPPORTED_VERSION = -32022;

    public final errorCode:Int;
    public final data:Null<Dynamic>;
    public final status:Int;

    public function new(code:Int, message:String, ?data:Dynamic, status:Int = 200) {
        super(message);
        this.errorCode = code;
        this.data = data;
        this.status = status;
    }
}

/** Which protocol revision a message uses: a 2025 revision or the stateless 2026-07-28 one. **/
enum McpEra {
    Legacy;
    Modern(revision:String);
}

/**
    A stateless MCP server: the tools, resources and prompts of one
    connection, built for each request. It answers JSON-RPC messages of the
    2025 revisions (after `initialize`) and of the 2026-07-28 revision,
    whose requests carry their protocol version and client details in
    `_meta` and are discovered with `server/discover`.
**/
class McpServer {
    public static inline var MODERN = "2026-07-28";
    public static inline var LATEST_LEGACY = "2025-11-25";
    public static inline var VERSION_KEY = "io.modelcontextprotocol/protocolVersion";
    public static inline var SERVER_INFO_KEY = "io.modelcontextprotocol/serverInfo";
    public static final legacyVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05", "2024-10-07"];

    /** Methods whose results clients may cache under the 2026-07-28 revision. **/
    static final cacheable = [
        "server/discover",
        "tools/list",
        "resources/list",
        "resources/templates/list",
        "resources/read",
        "prompts/list"
    ];

    public final name:String;
    public final version:String;
    public var instructions:Null<String>;

    final tools:Array<McpTool> = [];
    final resources:Array<McpResource> = [];
    final prompts:Array<McpPrompt> = [];
    final methods:Map<String, Dynamic->Dynamic> = [];
    final extensions:Dynamic = {};

    public function new(name:String, version:String, ?instructions:String) {
        this.name = name;
        this.version = version;
        this.instructions = instructions;
    }

    public function tool(definition:McpTool):Void {
        if (hasTool(definition.name)) {
            throw new Exception('The MCP tool ${definition.name} is already registered.');
        }
        tools.push(definition);
    }

    public function hasTool(name:String):Bool {
        return Lambda.exists(tools, entry -> entry.name == name);
    }

    public function resource(definition:McpResource):Void {
        resources.push(definition);
    }

    public function prompt(definition:McpPrompt):Void {
        prompts.push(definition);
    }

    /** Serves a method the protocol does not define, such as one of an extension. **/
    public function method(name:String, handler:Dynamic->Dynamic):Void {
        methods.set(name, handler);
    }

    public function extension(name:String, settings:Dynamic):Void {
        Reflect.setField(extensions, name, settings);
    }

    public function toolNames():Array<String> {
        return [for (entry in tools) entry.name];
    }

    public function capabilities():Dynamic {
        var result:Dynamic = {tools: {listChanged: true}};
        if (resources.length > 0) {
            result.resources = {listChanged: true};
        }
        if (prompts.length > 0) {
            result.prompts = {listChanged: true};
        }
        if (Reflect.fields(extensions).length > 0) {
            result.extensions = extensions;
        }
        return result;
    }

    /**
        The era of a JSON-RPC request or notification: the 2026-07-28
        revision when its `_meta` names a protocol version, otherwise a 2025
        revision. Throws for a malformed or unsupported version claim.
    **/
    public static function era(message:Dynamic):McpEra {
        var params:Dynamic = message.params;
        var meta:Dynamic = McpSchema.isObject(params) ? Reflect.field(params, "_meta") : null;
        if (!McpSchema.isObject(meta) || !Reflect.hasField(meta, VERSION_KEY)) {
            return Legacy;
        }
        var claimed:Dynamic = Reflect.field(meta, VERSION_KEY);
        if (!Std.isOfType(claimed, String)) {
            var reason = 'Invalid _meta envelope for protocol revision ${MODERN}: ${VERSION_KEY}: expected a protocol version string';
            throw new McpError(McpError.INVALID_PARAMS, reason, null, 400);
        }
        if (claimed != MODERN) {
            var data = {supported: [MODERN], requested: claimed};
            throw new McpError(McpError.UNSUPPORTED_VERSION,
                'Unsupported protocol version: ${claimed}', data, 400);
        }
        return Modern(claimed);
    }

    /**
        Answers one JSON-RPC message: a response object for a request, or
        `null` for a notification or a posted response.
    **/
    public function handle(message:Dynamic, era:McpEra):Null<Dynamic> {
        var id:Dynamic = Reflect.field(message, "id");
        var isRequest = Reflect.hasField(message, "id") && Reflect.hasField(message, "method");
        if (!isRequest) {
            return null;
        }
        try {
            var result = dispatch(message.method, message.params ?? {}, era);
            return {jsonrpc: "2.0", id: id, result: result};
        } catch (error:McpError) {
            return failure(id, error);
        }
    }

    public static function failure(id:Dynamic, error:McpError):Dynamic {
        var body:Dynamic = {code: error.errorCode, message: error.message};
        if (error.data != null) {
            body.data = error.data;
        }
        return {jsonrpc: "2.0", id: id, error: body};
    }

    function dispatch(method:String, params:Dynamic, era:McpEra):Dynamic {
        var modern = era != Legacy;
        var result:Dynamic = switch (method) {
            case "initialize" if (!modern):
                initialize(params);
            case "ping" if (!modern):
                {};
            case "server/discover" if (modern):
                discover();
            case "tools/list":
                {tools: [for (entry in tools) describeTool(entry)]};
            case "tools/call":
                callTool(params);
            case "resources/list":
                {resources: [for (entry in resources) describeResource(entry)]};
            case "resources/templates/list":
                {resourceTemplates: []};
            case "resources/read":
                readResource(params);
            case "prompts/list":
                {prompts: [for (entry in prompts) describePrompt(entry)]};
            case "prompts/get":
                getPrompt(params);
            default:
                var handler = methods.get(method);
                if (handler == null) {
                    throw new McpError(McpError.METHOD_NOT_FOUND, "Method not found", null,
                        modern ? 404 : 200);
                }
                handler(params);
        }
        if (!modern) {
            return result;
        }
        var enveloped:Dynamic = Reflect.copy(result);
        if (!Reflect.hasField(enveloped, "resultType")) {
            enveloped.resultType = "complete";
        }
        if (cacheable.contains(method)) {
            enveloped.ttlMs = 0;
            enveloped.cacheScope = "private";
        }
        var meta:Dynamic = {};
        Reflect.setField(meta, SERVER_INFO_KEY, {name: name, version: version});
        Reflect.setField(enveloped, "_meta", meta);
        return enveloped;
    }

    function initialize(params:Dynamic):Dynamic {
        var requested:Dynamic = params.protocolVersion;
        var negotiated = legacyVersions.contains(requested) ? requested : LATEST_LEGACY;
        var result:Dynamic = {
            protocolVersion: negotiated,
            capabilities: capabilities(),
            serverInfo: {name: name, version: version}
        };
        if (instructions != null) {
            result.instructions = instructions;
        }
        return result;
    }

    function discover():Dynamic {
        var result:Dynamic = {supportedVersions: [MODERN], capabilities: capabilities()};
        if (instructions != null) {
            result.instructions = instructions;
        }
        return result;
    }

    static function describeTool(entry:McpTool):Dynamic {
        var result:Dynamic = {
            name: entry.name,
            description: entry.description,
            inputSchema: entry.inputSchema,
            annotations: entry.annotations
        };
        if (entry.meta != null) {
            Reflect.setField(result, "_meta", entry.meta);
        }
        return result;
    }

    static function describeResource(entry:McpResource):Dynamic {
        return {
            uri: entry.uri,
            name: entry.name,
            mimeType: entry.mimeType,
            description: entry.description
        };
    }

    static function describePrompt(entry:McpPrompt):Dynamic {
        return {
            name: entry.name,
            title: entry.title,
            description: entry.description,
            arguments: entry.arguments
        };
    }

    function callTool(params:Dynamic):Dynamic {
        var toolName:Dynamic = params.name;
        var entry = Lambda.find(tools, candidate -> candidate.name == toolName);
        if (entry == null) {
            throw new McpError(McpError.INVALID_PARAMS, 'Tool ${toolName} not found');
        }
        var input:Dynamic = params.arguments ?? {};
        var values:Dynamic;
        try {
            values = McpSchema.apply(entry.inputSchema, input);
        } catch (error:McpSchemaError) {
            var reason = 'Input validation error: Invalid arguments for tool ${entry.name}: ${error.message}';
            return failedTool(reason);
        }
        try {
            return entry.run(values);
        } catch (error:McpError) {
            throw error;
        } catch (error:Exception) {
            return failedTool(error.message);
        } catch (error:Dynamic) {
            return failedTool(Std.string(error));
        }
    }

    public static function failedTool(message:String):Dynamic {
        return {content: [{type: "text", text: message}], isError: true};
    }

    /** A tool result carrying a JSON value as text and as structured content. **/
    public static function json(value:Dynamic):Dynamic {
        return {content: [{type: "text", text: Json.stringify(value)}], structuredContent: value};
    }

    function readResource(params:Dynamic):Dynamic {
        var uri:Dynamic = params.uri;
        var entry = Lambda.find(resources, candidate -> candidate.uri == uri);
        if (entry == null) {
            throw new McpError(McpError.INVALID_PARAMS, 'Resource not found: ${uri}', {uri: uri});
        }
        return {contents: [{uri: entry.uri, mimeType: entry.mimeType, text: entry.read()}]};
    }

    function getPrompt(params:Dynamic):Dynamic {
        var promptName:Dynamic = params.name;
        var entry = Lambda.find(prompts, candidate -> candidate.name == promptName);
        if (entry == null) {
            throw new McpError(McpError.INVALID_PARAMS, 'Prompt ${promptName} not found');
        }
        var values:Dynamic;
        try {
            values = McpSchema.apply(entry.argsSchema, params.arguments ?? {});
        } catch (error:McpSchemaError) {
            throw new McpError(McpError.INVALID_PARAMS,
                'Invalid arguments for prompt ${entry.name}: ${error.message}');
        }
        return entry.get(values);
    }
}
