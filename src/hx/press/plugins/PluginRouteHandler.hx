package hx.press.plugins;

import hx.well.handler.AbstractHandler;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.press.validation.ValidationResponder;

class PluginRouteHandler extends AbstractHandler implements ValidationResponder {
    var id:String;
    var directory:String;
    var handler:AbstractHandler;

    public function new(id:String, directory:String, handler:AbstractHandler) {
        super();
        this.id = id;
        this.directory = directory;
        this.handler = handler;
    }

    public function execute(request:Request):AbstractResponse {
        return PluginRuntime.route(id, directory, request, handler);
    }

    public override function validate():Bool {
        return PluginRuntime.validateRoute(id, directory, handler);
    }

    public function validationFailed(request:Request):AbstractResponse {
        return PluginRuntime.routeValidationFailure(id, directory, request, handler);
    }
}
