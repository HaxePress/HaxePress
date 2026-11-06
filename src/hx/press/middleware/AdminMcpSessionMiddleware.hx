package hx.press.middleware;

import hx.press.ai.AdminMcpAccess;
import hx.press.ai.AdminMcpAccess.AdminMcpError;
import hx.press.ai.AdminMcpPolicy;
import hx.well.http.Request;
import hx.well.http.RequestStatic;
import hx.well.http.Response;
import hx.well.http.ResponseBuilder;
import hx.well.middleware.CsrfMiddleware;
import hx.well.middleware.SessionMiddleware;
import hx.well.session.Session;
import hx.well.session.SessionDataType;

/** Trusted loopback tools enter the native admin stack with a request-only session. */
class AdminMcpSessionMiddleware extends SessionMiddleware {
    public override function handle(request:Request, next:Request->Null<Response>):Null<Response> {
        if (request.getAttribute(AdminMcpAccess.INTERNAL, false)) {
            return next(request);
        }
        if (request.header(AdminMcpAccess.TICKET_HEADER) == null) {
            return super.handle(request, next);
        }
        var actor;
        try {
            actor = AdminMcpAccess.delegated(request);
        } catch (error:AdminMcpError) {
            return ResponseBuilder.asJson({code: error.reason, error: error.message}, error.status);
        }
        if (actor == null || !AdminMcpPolicy.permits(request, actor.admin)) {
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
        session.sessionKey = actor.sessionKey;
        session.putWithEnum(SessionDataType.AUTH_ID("admin"), actor.admin.id);
        session.put("auth_version", actor.admin.password);
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
