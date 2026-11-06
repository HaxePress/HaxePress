package hx.press;

import haxe.Int64;
import haxe.Json;
import haxe.ds.StringMap;
import hx.press.TagData.TagRecord;
import hx.press.content.ContentTypeDefinition;
import hx.press.i18n.I18n;
import hx.press.media.MediaReferences;
import hx.press.view.View;
import hx.press.view.types.ContentViews.TagView;
import hx.press.view.types.EditorViews.ContentEditorView;
import hx.press.view.types.EditorViews.EditorContentTypeView;
import hx.press.view.types.EditorViews.EditorItemView;
import hx.press.view.types.EditorViews.EditorSeedView;
import hx.press.view.types.EditorViews.EditorWorkingCopyView;
import hx.well.http.Request;

/** The editor page's state, as `ContentController.renderEditor` prepares it. */
typedef ContentEditorState = {
    var detail:Dynamic;
    var type:ContentTypeDefinition;
    var isNew:Bool;
    var hasCategories:Bool;
    var categories:Array<String>;
    var draftKey:String;
    var workingCopy:Dynamic;
    var canPublish:Bool;
    var notice:String;
}

/**
    Prepares the data of the `content-editor` island: the saved item, the
    collection settings and the unsaved values to restore. It keeps only the
    fields the editor reads, so the page carries no other record data.
**/
class ContentEditorData {
    /** Editor fields that a working copy or a failed submission restores. */
    static final restoredFields = [
        "title",
        "slug",
        "excerpt",
        "content",
        "category",
        "image",
        "image_alt",
        "status",
        "featured",
        "published_at",
        "seo_title",
        "seo_description",
        "scheduled_epoch",
        "custom_fields"
    ];

    static final labelPatterns = [
        "create" => "Create {type}",
        "edit" => "Edit {type}",
        "save" => "Save {type}",
        "title" => "{type} title"
    ];

    public static function view(request:Request, state:ContentEditorState):ContentEditorView {
        var headingKey = state.isNew ? "create" : "edit";
        var workingCopy = state.workingCopy;
        var workingCopyView:Null<EditorWorkingCopyView> = workingCopy == null ? null : {
            key: workingCopy.key,
            baseVersion: workingCopy.baseVersion,
            version: workingCopy.version,
            updatedAt: workingCopy.updatedAt
        };
        return {
            heading: label(state.type, headingKey),
            item: item(state.detail),
            contentType: contentType(state.type),
            isNew: state.isNew,
            hasCategories: state.hasCategories,
            categories: state.categories,
            draftKey: state.draftKey,
            workingCopy: workingCopyView,
            seed: seed(request, workingCopy),
            canPublish: state.canPublish,
            notice: state.notice,
            mediaRules: MediaReferences.rules()
        };
    }

    /** A collection label such as "Edit Entry", translated like the editor's `collectionLabel`. */
    public static function label(type:ContentTypeDefinition, key:String):String {
        var explicit:Dynamic = type.labels == null ? null : Reflect.field(type.labels, key);
        if (explicit != null && explicit != "") {
            return I18n.t(Std.string(explicit));
        }
        var pattern = labelPatterns.get(key) ?? type.singular;
        return I18n.t(pattern, ["type" => type.singular]);
    }

    /**
        The submitted values of an editor save that failed validation. The
        handler redirects back with them flashed, so the editor can restore
        what the author typed.
    **/
    static function submittedValues(request:Request):Null<Map<String, String>> {
        if (!View.errors(request, null).exists("content")) {
            return null;
        }
        var values:Dynamic = View.flashed(request, "old");
        return Std.isOfType(values, StringMap) ? cast values : null;
    }

    static function item(detail:Dynamic):EditorItemView {
        var tagRecords:Array<Dynamic> = detail.tags ?? [];
        var fields = record(detail.fields);
        return {
            id: detail.id ?? 0,
            title: text(detail.title),
            slug: text(detail.slug),
            excerpt: text(detail.excerpt),
            content: text(detail.content),
            category: text(detail.category),
            image: text(detail.image),
            image_alt: text(detail.image_alt),
            status: text(detail.status),
            featured: detail.featured == true,
            published_at: text(detail.published_at).substr(0, 10),
            version: detail.version ?? 1,
            seo_title: text(detail.seo_title),
            seo_description: text(detail.seo_description),
            scheduled_epoch: epochText(detail.scheduled_epoch),
            tags: tags(tagRecords),
            fields: fields
        };
    }

    static function contentType(type:ContentTypeDefinition):EditorContentTypeView {
        var labels:Map<String, String> = [];
        if (type.labels != null) {
            for (key in Reflect.fields(type.labels)) {
                labels.set(key, text(Reflect.field(type.labels, key)));
            }
        }
        return {
            name: type.name,
            singular: type.singular,
            adminBase: type.adminBase,
            publicBase: type.publicBase,
            features: type.features,
            fields: type.fields,
            labels: labels,
            minimumTitleLength: type.minimumTitleLength,
            minimumExcerptLength: type.minimumExcerptLength
        };
    }

    static function seed(request:Request, workingCopy:Dynamic):Null<EditorSeedView> {
        var submitted = submittedValues(request);
        if (submitted != null) {
            var submittedFields = restoredFields.concat(["tags", "version"]);
            var values:Map<String, String> = [];
            for (field in submittedFields) {
                var value = submitted.get(field);
                if (value != null) {
                    values.set(field, value);
                }
            }
            var selectedTags = TagData.parse(submitted.get("tags") ?? "");
            return {values: values, tags: selectedTags == null ? null : tags(selectedTags)};
        }
        if (workingCopy == null || workingCopy.data == null) {
            return null;
        }
        var data:Dynamic = workingCopy.data;
        var values:Map<String, String> = [];
        for (field in restoredFields) {
            var value = formValue(Reflect.field(data, field));
            if (value != null) {
                values.set(field, value);
            }
        }
        var tagRecords:Null<Array<Dynamic>> = Reflect.field(data, "tagRecords");
        return {values: values, tags: tagRecords == null ? null : tags(tagRecords)};
    }

    static function tags(records:Array<Dynamic>):Array<TagView> {
        return [
            for (record in records)
                {
                    id: record.id,
                    name: text(record.name),
                    slug: text(record.slug),
                    description: text(record.description)
                }
        ];
    }

    /** A stored editor value as the text a form field holds. */
    static function formValue(value:Dynamic):Null<String> {
        if (value == null) {
            return null;
        }
        if (Std.isOfType(value, Bool)) {
            return value == true ? "1" : "0";
        }
        if (Std.isOfType(value, String)) {
            return value;
        }
        if (Std.isOfType(value, Int)) {
            return Std.string(value);
        }
        if (Std.isOfType(value, Float)) {
            var number:Float = value;
            var whole = Math.isFinite(number) && number == Math.ffloor(number);
            return whole ? Int64.toStr(Int64.fromFloat(number)) : Std.string(number);
        }
        return Json.stringify(value);
    }

    static function epochText(value:Dynamic):String {
        if (value == null || !(Std.isOfType(value, Float) || Std.isOfType(value, Int))) {
            return "";
        }
        var epoch:Float = value;
        if (!Math.isFinite(epoch) || epoch <= 0) {
            return "";
        }
        return Int64.toStr(Int64.fromFloat(Math.ffloor(epoch)));
    }

    /** An object of values as a map, so it is written as a JSON object. */
    static function record(value:Dynamic):Map<String, Dynamic> {
        var values:Map<String, Dynamic> = [];
        if (value == null) {
            return values;
        }
        if (Std.isOfType(value, StringMap)) {
            var source:StringMap<Dynamic> = cast value;
            for (key => item in source) {
                values.set(key, item);
            }
            return values;
        }
        for (key in Reflect.fields(value)) {
            values.set(key, Reflect.field(value, key));
        }
        return values;
    }

    static function text(value:Dynamic):String {
        return value == null ? "" : Std.string(value);
    }
}
