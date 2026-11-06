package hx.press;

import hx.press.AdminController;
import hx.press.content.ContentTypes;
import hx.press.model.ContentItem;
import hx.press.model.ContentType;
import hx.press.view.View;
import hx.well.http.Request;

using StringTools;

typedef AdminContentChoice = {
    var id:Int;
    var title:String;
}

typedef AdminCollectionChoice = {
    var key:String;
    var name:String;
}

/**
    Form state for server-rendered admin pages: the values of a failed
    submission, the page to return to, edited record identifiers and the
    selected entries of option pickers.
**/
class AdminForms {
    static final identifier = ~/^[1-9][0-9]{0,8}$/;

    /** Whether the previous submission failed with the field `marker` among its values. **/
    public static function resubmitted(request:Request, marker:String):Bool {
        return View.old(request, marker) != null;
    }

    /** A value of the failed submission, or `fallback` when the form did not send it. **/
    public static function old(request:Request, field:String, fallback:String):String {
        return View.old(request, field) ?? fallback;
    }

    /** The record identifier in the `edit` query value, or 0. **/
    public static function editId(request:Request):Int {
        var editing = request.query("edit", "");
        return identifier.match(editing) ? Std.parseInt(editing) : 0;
    }

    /**
        The page a failed submission returns to: `path` with `parameters`,
        and `edit` when the form sent the identifier of an existing record.
    **/
    public static function returnUrl(request:Request, path:String,
            ?parameters:Map<String, String>):String {
        var query:Array<String> = [];
        if (parameters != null) {
            for (name => value in parameters) {
                if (value != "") {
                    query.push('${name}=${value.urlEncode()}');
                }
            }
        }
        var submittedId = AdminController.input(request, "id", 16);
        if (identifier.match(submittedId)) {
            query.push('edit=${submittedId}');
        }
        var search = query.join("&");
        return query.length == 0 ? path : '${path}?${search}';
    }

    /** A stored key as the translation key of its label: `writer` becomes `Writer`. **/
    public static function label(key:String):String {
        var first = key.substr(0, 1).toUpperCase();
        var rest = key.substr(1);
        return '${first}${rest}';
    }

    /** The published public content item `id`, for the selected option of a content picker. **/
    public static function publishedContent(id:Int):Null<AdminContentChoice> {
        if (id <= 0) {
            return null;
        }
        var item = ContentItem.query.select(["id", "title"])
            .where("id", id)
            .where("status", "published")
            .whereInQuery("content_type", ContentTypes.publicKeys())
            .limit(1)
            .first();
        if (item == null) {
            return null;
        }
        var choice:AdminContentChoice = {id: item.id, title: item.title};
        return choice;
    }

    /** The public collection `key`, with an archive when `archives` is set, for a collection picker. **/
    public static function publicCollection(key:String, archives:Bool):Null<AdminCollectionChoice> {
        if (key == "") {
            return null;
        }
        var type = ContentTypes.find(key);
        if (type == null || !type.publicVisible || (archives && !type.hasArchive)) {
            return null;
        }
        var choice:AdminCollectionChoice = {key: type.key, name: type.name};
        return choice;
    }

    /** The first public collections by name, as the homepage collection select lists them. **/
    public static function publicCollections(limit:Int = 20):Array<AdminCollectionChoice> {
        var query = ContentTypes.accessible(ContentType.query.select(["key", "name"]), ["*"])
            .where("public_visible", 1)
            .orderBy("name")
            .orderBy("key")
            .limit(limit);
        var rows:Array<AdminCollectionChoice> = query.get().map(model -> cast model.toObject());
        return rows;
    }
}
