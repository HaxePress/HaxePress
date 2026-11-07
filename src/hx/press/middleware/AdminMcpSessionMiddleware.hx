package hx.press.middleware;

import hx.press.ai.AdminMcpAccess;
import hx.press.ai.AdminMcpAccess.AdminMcpError;
import hx.press.ai.AdminMcpAccess.AdminMcpGrant;
import hx.press.ai.AdminMcpPolicy;
import hx.well.http.Request;
import hx.well.http.RequestStatic;
import hx.well.http.Response;
import hx.well.http.ResponseBuilder;
import hx.well.middleware.CsrfMiddleware;
import hx.well.middleware.SessionMiddleware;
import hx.well.session.Session;
import hx.well.session.SessionDataType;

/**
    MCP requests enter the native admin stack with a request-only session:
    in-process requests of an MCP connection, and the preview browser's
    capture requests. Each is checked against the account's role areas
    before the route runs.
**/
class AdminMcpSessionMiddleware extends SessionMiddleware {
    public override function handle(request:Request, next:Request->Null<Response>):Null<Response> {
        if (request.getAttribute(AdminMcpAccess.INTERNAL, false)) {
            return next(request);
        }
        var grant:Null<AdminMcpGrant> = request.getAttribute(AdminMcpAccess.ACTOR, null);
        if (grant == null && request.header(AdminMcpAccess.TICKET_HEADER) == null) {
            return super.handle(request, next);
        }
        if (grant == null) {
            try {
                grant = AdminMcpAccess.delegated(request);
            } catch (error:AdminMcpError) {
                return ResponseBuilder.asJson({code: error.reason, error: error.message},
                    error.status);
            }
        }
        if (grant == null || !AdminMcpPolicy.permits(request, grant.admin)) {
            return
                ResponseBuilder.asJson({error: "This action requires the administration panel."},
                    403);
        }
        var csrf = request.header("X-CSRF-TOKEN", "");
        if (!~/^[A-Za-z0-9_-]{32}$/.match(csrf)) {
            return ResponseBuilder.asJson({error: "The MCP request could not be authenticated."},
                403);
        }
        var session = new AdminMcpRequestSession();
        session.sessionKey = grant.sessionKey;
        session.putWithEnum(SessionDataType.AUTH_ID("admin"), grant.admin.id);
        session.put("auth_version", grant.admin.password);
        session.put(CsrfMiddleware.TOKEN_KEY, csrf);
        request.session = session;
        request.setAttribute(AdminMcpAccess.INTERNAL, true);
        return next(request);
    }

    public override function dispose():Void {
        if (!RequestStatic.request().getAttribute(AdminMcpAccess.INTERNAL, false)) {
            super.dispose();
        }
    }
}

private class AdminMcpRequestSession extends Session {
    public override function save():Bool {
        return false;
    }

    public override function touch():Void {}
}
