package hx.press.content;

import hx.press.Activity;
import hx.press.AdminController;
import hx.press.CmsAccess;
import hx.press.CmsController;
import hx.press.Pagination;
import hx.press.SiteController;
import hx.press.content.ContentTypeForm;
import hx.press.view.View;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.ResponseBuilder;
import hx.press.model.ContentType;

class ContentTypeController {
    public static function index(request:Request):AbstractResponse {
        if (!CmsAccess.hasContentAccess() && !CmsAccess.can("settings")) {
            return CmsController.forbidden(request);
        }
        var search = StringTools.trim(request.query("q", "")).substr(0, 100);
        var cursor = Pagination.cursor(request, true);
        var author = CmsAccess.can("edit_others") ? 0 : CmsAccess.current().id;
        var capabilities = CmsAccess.can("settings") ? ["*"] : CmsAccess.capabilities(CmsAccess.current()
            .role);
        var page = ContentTypes.page(search, cursor, author, capabilities);
        var count = ContentTypes.count(search, capabilities);
        var links = Pagination.links("/admin/collections", ["q" => search], page, cursor, count,
            type -> type.key, type -> null);
        var collections = page.items.map(type -> {
            var row:Dynamic = Reflect.copy(type);
            var owned = type.owner != null && type.owner != "";
            row.active = type.enabled == 1 && (!owned || (type.owner_active ?? 0) > 0);
            return row;
        });
        var props = {
            collections: collections,
            pagination: links,
            query: search,
            canManage: CmsAccess.can("settings"),
            notice: request.query("notice", "")
        };
        return View.render("Admin/Collections", props);
    }

    public static function editor(request:Request, creating:Bool = false, error:String = "",
            status:Int = 200):AbstractResponse {
        if (!CmsAccess.can("settings")) {
            return CmsController.forbidden(request);
        }
        var key = creating ? "" : request.route("key");
        var type = creating ? null : ContentTypes.find(key, false);
        if (!creating && type == null) {
            return SiteController.notFound(request);
        }
        var redirect = AdminController.validationRedirect(request, "structure", error,
            creating ? "/admin/content-types/new" : '/admin/content-types/${key}/edit');
        if (redirect != null) {
            return redirect;
        }
        // A redirected or failed form submission is shown again as submitted.
        var flashed:Dynamic = View.flashed(request, "old");
        var source:Dynamic = flashed != null ? flashed : error != "" ? request.all() : null;
        var submitted = source == null ? null : ContentTypeForm.reader(source);
        var system = type != null && type.system;
        var input:Dynamic = ContentTypeForm.initial(type);
        if (submitted != null && ContentTypeForm.submitted(submitted)) {
            input = ContentTypeForm.read(submitted, system);
        }
        var props:Map<String, Dynamic> = [
            "definition" => type,
            "isNew" => creating,
            "supportedFeatures" => ContentTypes.supportedFeatures,
            "fieldKinds" => ContentTypes.fieldKinds,
            "notice" => request.query("notice", ""),
            "typeForm" => ContentTypeForm.view(input, type, creating),
            "kindOptions" => ContentTypeForm.kindOptions()
        ];
        if (error != "") {
            props.set("errors", ["structure" => error]);
        }
        return View.render("Admin/ContentTypeEditor", props).status(status);
    }

    public static function remove(request:Request):AbstractResponse {
        if (!CmsAccess.can("settings")) {
            return CmsController.forbidden(request);
        }
        var key = request.route("key");
        try {
            ContentTypes.remove(key);
            Activity.record("deleted", "content_type", 0, key);
            return ResponseBuilder.asRedirect("/admin/collections?notice=removed", 303);
        } catch (error:Dynamic) {
            return editor(request, false, Std.string(error), 422);
        }
    }

    public static function options(request:Request):AbstractResponse {
        if (!CmsAccess.can("settings") && !CmsAccess.can("navigation")
            && !CmsAccess.hasContentAccess()) {
            return CmsController.forbidden(request);
        }
        var search = StringTools.trim(request.query("q", "")).substr(0, 100);
        var capabilities = CmsAccess.can("settings")
            || CmsAccess.can("navigation") ? ["*"] : CmsAccess.capabilities(CmsAccess.current()
                .role);
        var query = ContentTypes.accessible(ContentType.query.select(["key", "name", "public_path"]),
            capabilities);
        var publicOnly = request.query("public", "0") == "1"
            || (CmsAccess.can("navigation") && !CmsAccess.can("settings"));
        var archives = request.query("archives", "0") == "1";
        if (publicOnly) {
            query.where("public_visible", 1);
        }
        if (archives) {
            query.where("has_archive", 1);
        }
        if (search != "") {
            var escaped = StringTools.replace(StringTools.replace(StringTools.replace(search, "!",
                "!!"), "%", "!%"), "_", "!_");
            var pattern = '%${escaped}%';
            query.whereLike("name", pattern);
        }
        var types:Array<Dynamic> = query.orderBy("name")
            .orderBy("key")
            .limit(20)
            .get()
            .map(model -> cast model.toObject());
        var selected = request.query("selected", "").substr(0, 32);
        var included = false;
        for (type in types) {
            if (type.key == selected) {
                included = true;
                break;
            }
        }
        if (!included && ContentTypes.validKey(selected)) {
            var chosen = ContentTypes.accessible(ContentType.query.select(["key", "name", "public_path"]),
                capabilities)
                .where("key", selected);
            if (publicOnly) {
                chosen.where("public_visible", 1);
            }
            if (archives) {
                chosen.where("has_archive", 1);
            }
            var selectedType = chosen.first();
            var extra:Dynamic = selectedType == null ? null : selectedType.toObject();
            if (extra != null) {
                types.push(extra);
            }
        }
        return ResponseBuilder.asJson({types: types});
    }
}
