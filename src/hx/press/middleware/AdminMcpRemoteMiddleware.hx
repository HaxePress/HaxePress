package hx.press.middleware;

import hx.press.ai.AdminMcpAccess;
import hx.press.ai.AdminMcpAccess.AdminMcpError;
import hx.press.ai.AdminMcpController;
import hx.press.themes.ThemeAiAccess;
import hx.well.http.Request;
import hx.well.http.Response;
import hx.well.http.ResponseBuilder;
import hx.well.middleware.AbstractMiddleware;

class AdminMcpRemoteMiddleware extends AbstractMiddleware {
    public function handle(request:Request, next:Request->Null<Response>):Null<Response> {
        // Only links this site generated exist; any other address is not found.
        if (!AdminMcpAccess.exists(request.route("id"))) {
            return ResponseBuilder.asJson({
                code: "not_found",
                error: "This MCP URL does not exist."
            }, 404).header("Cache-Control", "private, no-store");
        }
        if (!ThemeAiAccess.allowedOrigin(request.header("Origin", ""))) {
            return ResponseBuilder.asJson({error: "This MCP origin is not allowed."}, 403);
        }
        try {
            var actor = AdminMcpAccess.authenticate(request.route("id"),
                request.header("Authorization", ""));
            request.setAttribute(AdminMcpController.LINK, actor);
        } catch (error:AdminMcpError) {
            return AdminMcpController.rejected(error);
        }
        return next(request);
    }
}
