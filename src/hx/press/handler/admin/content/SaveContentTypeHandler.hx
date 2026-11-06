package hx.press.handler.admin.content;

import hx.well.handler.AbstractHandler;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.RequestStatic.request;
import hx.well.http.ResponseBuilder;
import hx.well.validator.ValidatorRule;
import hx.press.validation.ValidationResponder;
import hx.press.CmsAccess;
import hx.press.CmsController;
import hx.press.Activity;
import haxe.Json;
import hx.press.content.ContentTypeForm;
import hx.press.content.ContentTypes;
import hx.press.content.ContentTypeController;
import hx.press.content.ContentTypeDefinition;
import hx.press.view.View;

/**
    Saves a collection definition, sent either as a JSON `definition` or as
    the fields of the server-rendered editor form. The editor's field list
    buttons submit the same form with an `action` such as `add-field`; those
    redirect back to the editor with the changed draft instead of saving.
**/
class SaveContentTypeHandler extends AbstractHandler implements ValidationResponder {
    public override function validate():Bool {
        if (!CmsAccess.can("settings")) {
            return true;
        }
        var current = request();
        if (isEditorForm(current)) {
            // ContentTypes.save validates each submitted value and its length.
            return true;
        }
        return current.validate(["definition" => [Required, String, Min(1), Max(60000)]]);
    }

    public function validationFailed(request:Request):AbstractResponse {
        var creating = request.route("key") == null;
        return ContentTypeController.editor(request, creating,
            "The collection definition exceeds its size limit.", 422);
    }

    public function execute(request:Request):AbstractResponse {
        if (!CmsAccess.can("settings")) {
            return CmsController.forbidden(request);
        }
        var routeKey = request.route("key");
        var creating = routeKey == null;
        var existing = creating ? null : ContentTypes.find(routeKey, false);
        var form = isEditorForm(request);
        var submitted = ContentTypeForm.reader(request.all());
        var action = form ? submitted("action") ?? "" : "";
        try {
            var input:Dynamic;
            if (form) {
                var system = existing != null && existing.system;
                input = ContentTypeForm.read(submitted, system);
            } else {
                var values = request.only("definition");
                var source:String = values.get("definition");
                input = Json.parse(source);
            }
            if (action != "" && action != "save") {
                return fieldListAction(input, action, creating, existing);
            }
            if (!creating && (routeKey == null || routeKey != input.key)) {
                throw "Content type keys cannot be changed after creation.";
            }
            var owner = existing == null ? "" : existing.owner;
            var key = ContentTypes.save(input, owner, creating);
            Activity.record("saved", "content_type", 0, key);
            return ResponseBuilder.asRedirect('/admin/content-types/${key}/edit?notice=saved', 303);
        } catch (error:Dynamic) {
            return ContentTypeController.editor(request, creating, Std.string(error), 422);
        }
    }

    /** Adds, moves or removes a custom field of the draft and shows the editor again. **/
    function fieldListAction(input:Dynamic, action:String, creating:Bool,
            existing:Null<ContentTypeDefinition>):AbstractResponse {
        if (!creating && existing == null) {
            return ResponseBuilder.asRedirect("/admin/collections", 303);
        }
        var shown = ContentTypeForm.apply(input, action);
        View.flash("old", ContentTypeForm.values(input));
        var editorPath = creating ? "/admin/content-types/new" : '/admin/content-types/${existing.key}/edit';
        var anchor = shown >= 0 ? 'custom-field-${shown}' : "custom-fields";
        return ResponseBuilder.asRedirect('${editorPath}#${anchor}', 303);
    }

    static function isEditorForm(request:Request):Bool {
        var values = request.all();
        return !values.exists("definition")
            && ContentTypeForm.submitted(ContentTypeForm.reader(values));
    }
}
