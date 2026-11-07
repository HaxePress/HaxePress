package hx.press.ai;

import haxe.Exception;
import haxe.Json;
import haxe.crypto.Base64;
import haxe.crypto.Sha256;
import haxe.io.Bytes;
import hx.press.ai.AdminMcpAccess.AdminMcpGrant;
import hx.press.mcp.InternalRequest;
import hx.press.mcp.InternalRequest.InternalReply;
import hx.press.mcp.McpServer;
import hx.press.mcp.McpMediaInput;
import hx.well.internal.SecureToken;

typedef AdminImageReply = {
    var mimeType:String;
    var data:String;
    var size:Int;
    var sha256:String;
    var uploadId:Null<String>;
}

typedef AdminReply = {
    var status:Int;
    var redirect:Null<String>;
    var data:Null<Dynamic>;
    var image:Null<AdminImageReply>;
}

/**
    Calls the administration panel for an MCP connection: each call is an
    in-process request to a native admin route, made as the connected
    account and checked by `AdminMcpPolicy` and the route's own guards.
    Pages answer with their data instead of HTML.
**/
class AdminMcpBridge {
    static inline var MAX_DATA_BYTES = 4 * 1048576;
    static final imageTypes = ["image/png", "image/jpeg", "image/gif", "image/webp"];

    final grant:AdminMcpGrant;

    public function new(grant:AdminMcpGrant) {
        this.grant = grant;
    }

    public function admin():AdminMcpGrant {
        return grant;
    }

    public static function validPath(path:String):Bool {
        var lowered = path.toLowerCase();
        if (!~/^\/admin(?:[\/?]|$)/.match(path)
            || ~/[\\\x00-\x20#]/.match(path)
            || lowered.indexOf("%2e") >= 0
            || ~/(?:^|\/)\.{1,2}(?:[\/?]|$)/.match(path)
            || path.indexOf("//") >= 0) {
            return false;
        }
        return !~/^\/admin\/(login|logout|install)(?:[\/?]|$)/.match(path);
    }

    /** Sends a request to an admin route and returns its reply; failures throw their message. **/
    public function request(path:String, method:String = "GET", ?data:Dynamic,
            ?image:McpImage):AdminReply {
        if (!validPath(path)) {
            throw new Exception("Choose a relative route in the HaxePress administration panel.");
        }
        var headers:Map<String, String> = [
            "Accept" => "application/json",
            "X-Well-Data" => "true",
            "X-CSRF-TOKEN" => SecureToken.generate(32)
        ];
        var body:Null<Bytes> = null;
        if (method != "GET") {
            headers.set("Content-Type",
                image != null ? "application/octet-stream" : "application/json");
            body = image != null ? image.bytes : Bytes.ofString(Json.stringify(data ?? {}));
        }
        if (image != null && image.name != null) {
            headers.set("X-File-Name", StringTools.urlEncode(image.name));
        }
        var reply = InternalRequest.send(method, path, headers, body,
            [AdminMcpAccess.ACTOR => grant], McpMediaInput.MAX_IMAGE_BYTES);
        return interpret(reply);
    }

    static function header(reply:InternalReply, name:String):Null<String> {
        var lowered = name.toLowerCase();
        for (key => value in reply.headers) {
            if (key.toLowerCase() == lowered) {
                return value;
            }
        }
        return null;
    }

    static function interpret(reply:InternalReply):AdminReply {
        var contentType = (header(reply, "Content-Type") ?? "").split(";")[0];
        var status = reply.status;
        var ok = status >= 200 && status < 300;
        if (ok && imageTypes.contains(contentType)) {
            return {
                status: status,
                redirect: null,
                data: null,
                image: {
                    mimeType: contentType,
                    data: Base64.encode(reply.body),
                    size: reply.body.length,
                    uploadId: header(reply, "X-Upload-Id"),
                    sha256: Sha256.make(reply.body).toHex()
                }
            };
        }
        if (reply.body.length > MAX_DATA_BYTES) {
            throw new Exception("The CMS response exceeds its size limit.");
        }
        var parsed:Dynamic = null;
        if (contentType == "application/json" && reply.body.length > 0) {
            parsed = Json.parse(reply.body.toString());
        }
        if (!ok && (status < 300 || status >= 400)) {
            throw new Exception(errorMessage(parsed) ?? 'The admin route returned HTTP ${status}.');
        }
        var redirect = header(reply, "Location");
        if (header(reply, "X-Well-Data") == "true" && parsed != null && parsed.props != null) {
            var props:Dynamic = Reflect.copy(parsed.props);
            Reflect.deleteField(props, "csrfToken");
            Reflect.deleteField(props, "i18n");
            return {
                status: status,
                redirect: redirect,
                data: {component: parsed.component, props: props},
                image: null
            };
        }
        return {
            status: status,
            redirect: redirect,
            data: parsed,
            image: null
        };
    }

    static function errorMessage(parsed:Dynamic):Null<String> {
        if (parsed == null) {
            return null;
        }
        if (Std.isOfType(parsed.error, String)) {
            return parsed.error;
        }
        var props:Dynamic = parsed.props;
        if (props == null) {
            return null;
        }
        if (Std.isOfType(props.message, String)) {
            return props.message;
        }
        var errors:Dynamic = props.errors;
        if (errors != null && Type.typeof(errors) == TObject) {
            for (name in Reflect.fields(errors)) {
                var value:Dynamic = Reflect.field(errors, name);
                return Std.isOfType(value, String) ? value : null;
            }
        }
        return null;
    }

    /** The tool result of an admin reply: its status, redirect and data, or the image. **/
    public static function result(reply:AdminReply):Dynamic {
        if (reply.image != null) {
            var info = {
                size: reply.image.size,
                sha256: reply.image.sha256,
                uploadId: reply.image.uploadId
            };
            var content:Array<Dynamic> = [
                {type: "text", text: Json.stringify(info)},
                {type: "image", mimeType: reply.image.mimeType, data: reply.image.data}
            ];
            return {
                content: content,
                structuredContent: {
                    status: reply.status,
                    size: info.size,
                    sha256: info.sha256,
                    uploadId: info.uploadId
                }
            };
        }
        var value:Dynamic = {status: reply.status};
        if (reply.redirect != null) {
            value.redirect = reply.redirect;
        }
        if (reply.data != null) {
            value.data = reply.data;
        }
        return McpServer.json(value);
    }
}
