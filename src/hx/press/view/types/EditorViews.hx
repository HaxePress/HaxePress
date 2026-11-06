package hx.press.view.types;

import hx.press.view.types.ContentViews.FieldDefinitionView;
import hx.press.view.types.ContentViews.TagView;

/** The image upload rules the content editor checks before it uploads a file. */
@:well.view
typedef EditorMediaRulesView = {
    var uploadUrl:String;
    var maxBytes:Int;
    var mimeTypes:Array<String>;
    var extensions:Array<String>;
    var imagePattern:String;
}

/** The collection settings the content editor reads. */
@:well.view
typedef EditorContentTypeView = {
    var name:String;
    var singular:String;
    var adminBase:String;
    var publicBase:String;
    var features:Array<String>;
    var fields:Array<FieldDefinitionView>;
    var labels:Map<String, String>;
    var minimumTitleLength:Int;
    var minimumExcerptLength:Int;
}

/** The saved values of the content item in the editor. */
@:well.view
typedef EditorItemView = {
    var id:Int;
    var title:String;
    var slug:String;
    var excerpt:String;
    var content:String;
    var category:String;
    var image:String;
    var image_alt:String;
    var status:String;
    var featured:Bool;
    var published_at:String;
    var version:Int;
    var seo_title:String;
    var seo_description:String;

    /** Milliseconds since the epoch as text, or an empty string. */
    var scheduled_epoch:String;

    var tags:Array<TagView>;
    var fields:Map<String, Dynamic>;
}

/** A private working copy of the editor's values. */
@:well.view
typedef EditorWorkingCopyView = {
    var key:String;
    var baseVersion:Int;
    var version:Int;
    var updatedAt:String;
}

/**
    Unsaved editor values to restore, from a working copy or a submission
    that failed validation. `values` uses the form field names; `tags` is
    null when the item's saved tags apply.
**/
@:well.view
typedef EditorSeedView = {
    var values:Map<String, String>;
    var tags:Null<Array<TagView>>;
}

/** Everything the `content-editor` island needs besides the request roots. */
@:well.view
typedef ContentEditorView = {
    var heading:String;
    var item:EditorItemView;
    var contentType:EditorContentTypeView;
    var isNew:Bool;
    var hasCategories:Bool;
    var categories:Array<String>;
    var draftKey:String;
    var workingCopy:Null<EditorWorkingCopyView>;
    var seed:Null<EditorSeedView>;
    var canPublish:Bool;
    var notice:String;
    var mediaRules:EditorMediaRulesView;
}
