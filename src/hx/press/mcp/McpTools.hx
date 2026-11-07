package hx.press.mcp;

import hx.press.mcp.McpSchema.McpField;
import hx.press.mcp.McpServer.McpToolHandler;

/** Shared tool annotations and a shorthand for registering tools. **/
class McpTools {
    public static final readOnly:Dynamic = {
        readOnlyHint: true,
        destructiveHint: false,
        openWorldHint: false
    };
    public static final edit:Dynamic = {
        readOnlyHint: false,
        destructiveHint: true,
        openWorldHint: false
    };

    /**
        Registers a tool whose input is an object with `fields`. A failing
        handler becomes a tool error that carries its message.
    **/
    public static function add(server:McpServer, name:String, description:String,
            fields:Array<McpField>, isReadOnly:Bool, run:McpToolHandler, ?meta:Dynamic):Void {
        server.tool({
            name: name,
            description: description,
            inputSchema: McpSchema.input(fields),
            annotations: isReadOnly ? readOnly : edit,
            meta: meta,
            run: run
        });
    }

    /** Registers a tool with a complete JSON Schema, such as one a plugin declares. **/
    public static function addSchema(server:McpServer, name:String, description:String,
            inputSchema:Dynamic, isReadOnly:Bool, run:McpToolHandler, ?meta:Dynamic):Void {
        server.tool({
            name: name,
            description: description,
            inputSchema: inputSchema,
            annotations: isReadOnly ? readOnly : edit,
            meta: meta,
            run: run
        });
    }
}
