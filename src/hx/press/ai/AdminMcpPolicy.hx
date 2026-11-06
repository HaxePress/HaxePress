package hx.press.ai;

import haxe.Json;
import hx.press.access.Roles;
import hx.press.model.Admin;
import hx.press.themes.ThemeAiPermissions;
import hx.well.http.Request;
import hx.well.route.Route;
import hx.well.route.RouteElement;
import hx.well.type.AttributeType;

class AdminMcpPolicy {
    public static function allows(path:String, method:String):Bool {
        path = normalize(path);
        if (method != "GET" && method != "POST" && method != "DELETE") {
            return false;
        }
        if (!within(path, "/admin")) {
            return false;
        }
        for (prefix in ["/admin/login", "/admin/logout", "/admin/password", "/admin/install"]) {
            if (within(path, prefix)) {
                return false;
            }
        }
        if (within(path, "/admin/ai")) {
            return method == "GET"
                && (path == "/admin/ai/routes"
                    || ~/^\/admin\/ai\/media\/[0-9]+(?:\/info)?$/.match(path));
        }
        if (within(path, "/admin/backups")) {
            return path == "/admin/backups" && method == "GET";
        }
        if (~/^\/admin\/themes\/[^\/]+\/ai(?:\/|$)/.match(path)) {
            return false;
        }
        if (method == "GET") {
            return true;
        }
        if (within(path, "/admin/team")
            || within(path, "/admin/roles")
            || within(path, "/admin/plugins/github")
            || ~/^\/admin\/(plugins|themes)\/(upload|install|discard)$/.match(path)
            || ~/^\/admin\/themes\/[^\/]+\/(enable|disable|uninstall)$/.match(path)) {
            return false;
        }
        return true;
    }

    public static function permits(request:Request, admin:Admin):Bool {
        var path = normalize(request.path);
        if (!allows(path, request.method)) {
            return false;
        }
        var route:RouteElement = request.getAttribute(AttributeType.RouteElement);
        var metadata = pluginMetadata(route);
        if (metadata != null && !Roles.can(admin.role, metadata.capability)) {
            return false;
        }
        var themeId = request.route("id");
        if (themeId == null || !within(path, "/admin/themes")) {
            return true;
        }
        var permissions = ThemeAiPermissions.forAdmin(themeId, admin.id,
            Roles.can(admin.role, "media"));
        var write = request.method != "GET";
        if (!permissions.read || (write && !permissions.edit)) {
            return false;
        }
        return !write || path != '/admin/themes/${themeId}/design'
            || request.input("action", "") == "save";
    }

    public static function pluginTools(grants:Array<String>):Array<Dynamic> {
        var tools:Array<Dynamic> = [];
        var used:Map<String, Bool> = [];
        for (route in Route.routes) {
            var definition = pluginMetadata(route);
            if (definition == null
                || route.value.indexOf("{") >= 0
                || !route.getMethods().contains(definition.method)
                || !allows(route.value, definition.method)
                || !(grants.contains("*") || grants.contains(definition.capability))
                || used.exists(definition.name)) {
                continue;
            }
            used.set(definition.name, true);
            tools.push({
                name: definition.name,
                description: definition.description,
                path: route.value,
                method: definition.method,
                inputSchema: definition.inputSchema
            });
            if (tools.length == 64) {
                break;
            }
        }
        return tools;
    }

    static function pluginMetadata(route:Null<RouteElement>):Dynamic {
        if (route == null) {
            return null;
        }
        var plugin:String = route.getAttribute("hx.press.plugin", "");
        var metadata:Dynamic = route.getAttribute("cms.mcp", null);
        if (!StringTools.startsWith(plugin, "plugin-")
            || metadata == null
            || !(metadata.name is String)
            || !~/^[a-z][a-z0-9_]{0,47}$/.match(metadata.name)
            || !(metadata.description is String)
            || metadata.description.length > 500
            || metadata.inputSchema == null
            || metadata.inputSchema.type != "object"
            || Json.stringify(metadata.inputSchema).length > 4096) {
            return null;
        }
        var namespace = StringTools.replace(plugin, "-", "_");
        var name = '${namespace}_${metadata.name}';
        if (name.length > 64) {
            return null;
        }
        var capability:String = metadata.capability is String ? metadata.capability : "extensions";
        var method:String = metadata.method is String ? metadata.method : "GET";
        return {
            name: name,
            description: metadata.description,
            inputSchema: metadata.inputSchema,
            capability: capability,
            method: method
        };
    }

    public static function routes():Array<{path:String, methods:Array<String>}> {
        var result:Array<{path:String, methods:Array<String>}> = [];
        for (route in Route.routes) {
            if (route.getWsHandler() != null || route.value == "/admin/ai/routes") {
                continue;
            }
            var methods:Array<String> = [];
            for (method in route.getMethods()) {
                if (allows(route.value, method)) {
                    methods.push(method);
                }
            }
            if (methods.length > 0) {
                result.push({path: route.value, methods: methods});
            }
        }
        return result;
    }

    static function within(path:String, prefix:String):Bool {
        return path == prefix || StringTools.startsWith(path, '${prefix}/');
    }

    static function normalize(path:Null<String>):String {
        if (path == null) {
            return "";
        }
        return StringTools.endsWith(path, "/") ? path.substr(0, path.length - 1) : path;
    }
}
