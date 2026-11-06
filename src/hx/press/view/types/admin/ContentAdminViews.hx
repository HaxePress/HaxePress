package hx.press.view.types.admin;

import wellout.Url;

/** A collection shortcut on the dashboard. */
@:well.view
typedef ContentAdminCollectionCardView = {
    var key:String;
    var name:String;
    var singular:String;
    var admin_path:String;
    var icon:String;
    var items:Int;
}

/** A dashboard activity entry. */
@:well.view
typedef ContentAdminActivityView = {
    var id:Int;
    var actor:String;
    var action:String;
    var label:String;
    var created_at:String;
    var mcp:Bool;
}

/** A custom field value prepared for a content list column. */
@:well.view
typedef ContentAdminColumnView = {
    var text:String;
    var translate:Bool;
}

/** A custom field shown as a content list column. */
@:well.view
typedef ContentAdminListFieldView = {
    var key:String;
    var label:String;
}

/** A row of the admin content table. */
@:well.view
typedef ContentAdminRowView = {
    var id:Int;
    var title:String;
    var status:String;
    var image:Url;
    var url:Url;
    var featured:Bool;
    var category:String;
    var updatedLabel:String;
    var adminBase:String;
    @:optional var columns:Array<ContentAdminColumnView>;
}

@:well.view
typedef ContentAdminTypeLabelsView = {
    var create:String;
    var description:String;
}

/** The collection a content list belongs to. */
@:well.view
typedef ContentAdminTypeView = {
    var key:String;
    var name:String;
    var singular:String;
    var description:String;
    var adminBase:String;
    var labels:ContentAdminTypeLabelsView;
}

/** A new working copy that has not been saved to its collection yet. */
@:well.view
typedef ContentAdminWorkingDraftView = {
    var key:String;
    var title:String;
}

/** A collection in the collections table. */
@:well.view
typedef ContentAdminCollectionView = {
    var key:String;
    var name:String;
    var icon:String;
    var admin_path:String;
    var public_path:String;
    var public_visible:Int;
    var owner:String;
    var items:Int;
    var active:Bool;
}

/** A checkbox or select choice: its value, translation key and state. */
@:well.view
typedef ContentAdminChoiceView = {
    var value:String;
    var label:String;
    var checked:Bool;
}

/** An interface label input of the collection editor. */
@:well.view
typedef ContentAdminLabelInputView = {
    var key:String;
    var label:String;
    var value:String;
}

/** A length constraint input of the collection editor. */
@:well.view
typedef ContentAdminLimitInputView = {
    var key:String;
    var label:String;
    var minimum:Int;
    var maximum:Int;
    var value:String;
}

/** A custom field definition as the collection editor shows it. */
@:well.view
typedef ContentAdminFieldFormView = {
    var key:String;
    var label:String;
    var kind:String;
    var help:String;
    var options:String;
    var required:Bool;
    var publicVisible:Bool;
    var filterable:Bool;
    var inList:Bool;
    var scalar:Bool;
    var canFilter:Bool;
}

/** The collection editor form, from the stored definition or a submitted draft. */
@:well.view
typedef ContentAdminTypeFormView = {
    var key:String;
    var name:String;
    var singular:String;
    var description:String;
    var publicPath:String;
    var icon:String;
    var position:String;
    var publicVisible:Bool;
    var hasArchive:Bool;
    var enabled:Bool;
    var dedicatedAccess:Bool;
    var template:String;
    var archiveTemplate:String;
    var features:Array<ContentAdminChoiceView>;
    var fields:Array<ContentAdminFieldFormView>;
    var fieldCount:Int;
    var canAddField:Bool;
    var labels:Array<ContentAdminLabelInputView>;
    var limits:Array<ContentAdminLimitInputView>;
    var savePath:String;
    var deletePath:String;
    var heading:String;
    var owner:String;
    var system:Bool;
    var removable:Bool;
}

/** A media library image. */
@:well.view
typedef ContentAdminMediaImageView = {
    var id:Int;
    var filename:String;
    var title:String;
    var alt:String;
    var url:Url;
    var width:Int;
    var height:Int;
    var kilobytes:Int;
    var can_delete:Bool;
    var references_verified:Bool;

    /** Days until the trash deletes the image; 0 outside the trash. **/
    var days_left:Int;
}

/** An image whose references the references dialog can show. */
@:well.view
typedef ContentAdminMediaReferenceView = {
    var id:Int;
    var filename:String;
    var title:String;
    var alt:String;
    var url:Url;
    var canDelete:Bool;
    var verified:Bool;
}

/** The upload limits the media uploader checks before sending a file. */
@:well.view
typedef ContentAdminMediaRulesView = {
    var uploadUrl:String;
    var maxBytes:Int;
    var mimeTypes:Array<String>;
    var extensions:Array<String>;
    var imagePattern:String;
}
