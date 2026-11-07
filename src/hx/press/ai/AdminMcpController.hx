package hx.press.ai;

import hx.press.CmsAccess;
import hx.press.access.Roles;
import hx.press.ai.AdminMcpAccess.AdminMcpActor;
import hx.press.ai.AdminMcpAccess.AdminMcpError;
import hx.press.mcp.McpEndpoint;
import hx.press.view.ViewRoots;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.ResponseBuilder;

class AdminMcpController {
    /** The authenticated link of a remote MCP request, set by `AdminMcpRemoteMiddleware`. **/
    public static inline var LINK = "hx.press.admin-mcp.link";

    public static function state(request:Request):AbstractResponse {
        return json(AdminMcpAccess.state(CmsAccess.current()));
    }

    public static function issue(request:Request):AbstractResponse {
        if (!request.validate([
            "profile" => [
                Required,
                String,
                Regex("^(chatgpt|claude|codex|gemini|cursor|copilot|grok|http)$")
            ],
            "hours" => [Int]
        ])) {
            return json({error: "Choose a supported MCP client."}, 422);
        }
        try {
            var hours:Int = request.input("hours", AdminMcpAccess.DEFAULT_LIFETIME);
            var issued = AdminMcpAccess.issue(CmsAccess.current(), request.input("profile"), hours);
            return json(issued, 201);
        } catch (error:AdminMcpError) {
            return rejected(error);
        }
    }

    /** Changes the expiry of a link no client has used yet. **/
    public static function expiry(request:Request):AbstractResponse {
        if (!request.validate(["hours" => [Required, Int]])) {
            return json({error: "Choose a supported expiry."}, 422);
        }
        try {
            var hours:Int = request.input("hours");
            AdminMcpAccess.changeExpiry(CmsAccess.current().id, request.route("id"), hours);
            return state(request);
        } catch (error:AdminMcpError) {
            return rejected(error);
        }
    }

    public static function end(request:Request):AbstractResponse {
        var admin = CmsAccess.current();
        try {
            AdminMcpAccess.end(admin.id, request.route("id"));
            return state(request);
        } catch (error:AdminMcpError) {
            return rejected(error);
        }
    }

    /** Streamable HTTP for a generated MCP link, served by this process. **/
    public static function endpoint(request:Request):AbstractResponse {
        var actor:AdminMcpActor = request.getAttribute(LINK);
        var grant = AdminMcpAccess.grant(actor);
        return McpEndpoint.http(request, () -> AdminMcpServer.create(grant),
            () -> AdminMcpAccess.recordSeen(actor.sessionId));
    }

    public static function routes(request:Request):AbstractResponse {
        if (!request.getAttribute(AdminMcpAccess.INTERNAL, false)) {
            return json({error: "An authenticated MCP request is required."}, 403);
        }
        var admin = CmsAccess.current();
        var capabilities = Roles.grants(admin.role);
        return json({
            navigation: ViewRoots.adminNavigation(request),
            routes: AdminMcpPolicy.routes(capabilities),
            capabilities: capabilities,
            tools: AdminMcpPolicy.pluginTools(capabilities)
        });
    }

    public static function rejected(error:AdminMcpError):AbstractResponse {
        var response = ResponseBuilder.asJson({code: error.reason, error: error.message},
            error.status)
            .header("Cache-Control", "private, no-store");
        if (error.status == 401) {
            var challenge = 'Bearer realm="haxepress"';
            if (error.reason != "authorization_required") {
                challenge += ', error="invalid_token"';
            }
            response.header("WWW-Authenticate", challenge);
        }
        return response;
    }

    static function json(data:Dynamic, status:Int = 200):AbstractResponse {
        return ResponseBuilder.asJson(data, status).header("Cache-Control", "private, no-store");
    }
}
