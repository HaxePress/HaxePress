package hx.press.view.types.admin;

import hx.press.view.types.ContentViews.PageLinksView;
import wellout.SafeHtml;
import wellout.Url;

/** An installed plugin or theme on `Admin/Extensions`, with its localized name and summary. */
@:well.view
typedef ExtensionPackageView = {
    var id:String;
    var version:String;
    var author:String;
    var enabled:Int;
    var last_error:String;
    var setting_count:Int;
    var restart_required:Int;
    var built_in:Bool;
    var designed:Bool;

    /** A packaged theme whose installed files can be downloaded as a ZIP. */
    var downloadable:Bool;

    /** A designed theme whose saved changes are not published yet. */
    var unpublished:Bool;

    var localizedName:String;
    var localizedDescription:String;

    /** The preview frame a theme thumbnail captures; empty for plugins. */
    var thumbnail:String;
}

/** A staged package upload waiting for installation. */
@:well.view
typedef ExtensionInspectionView = {
    var key:String;
    var name:String;
    var version:String;
    var description:String;
    var author:String;
    var serverLabel:String;
    var repository:String;
    var installedVersion:String;
    var builder:Bool;
    var replace:String;
}

@:well.view
typedef ExtensionReleaseAssetView = {
    var id:String;
    var name:String;
}

@:well.view
typedef ExtensionReleaseView = {
    var label:String;
    var assets:Array<ExtensionReleaseAssetView>;
}

/** The GitHub release picker; `loaded` once a repository's releases were listed. */
@:well.view
typedef ExtensionGitHubView = {
    var repository:String;
    var error:String;
    var page:String;
    var loaded:Bool;
    var releases:Array<ExtensionReleaseView>;
    @:optional var previous:Url;
    @:optional var next:Url;
}

@:well.view
typedef ExtensionPackageInfoView = {
    var id:String;
    var name:String;
    var version:String;
}

@:well.view
typedef ExtensionSettingOptionView = {
    var value:String;
    var label:String;
    var selected:Bool;
}

/** A package setting prepared for its form control; labels are localized. */
@:well.view
typedef ExtensionSettingFieldView = {
    var key:String;
    var kind:String;
    var label:String;
    var help:String;
    var required:Bool;
    var value:String;
    var inputType:String;
    var maxLength:Int;
    var minimum:String;
    var maximum:String;
    var checked:Bool;
    var colorValue:String;
    var colorEnabled:Bool;
    var secretSaved:Bool;
    var options:Array<ExtensionSettingOptionView>;
}

@:well.view
typedef RoleDefinitionView = {
    var key:String;
    var name:String;
    var description:String;
    var enabled:Int;
    var system:Int;
    var owner:String;
}

@:well.view
typedef RoleCapabilityView = {
    var key:String;
    var name:String;
    var group_name:String;
    var owner:String;
}

/** The role editor's form values: the stored role, or the input of a failed save. */
@:well.view
typedef RoleFormView = {
    var key:String;
    var name:String;
    var description:String;
    var enabled:Bool;
}

/** The installer's state; `step` is 0 (database), 1 (administrator) or 2 (review). */
@:well.view
typedef InstallSetupView = {
    var blocked:Bool;
    var message:String;
    var step:Int;
    var driver:String;
    var file:String;
    var host:String;
    var port:String;
    var database:String;
    var username:String;
    var verifiedLabel:String;
    var reviewDatabase:String;
    var siteName:String;
    var adminName:String;
    var adminEmail:String;

    /** Steps installation plugins offer here, such as restoring a backup. **/
    var panels:Array<SafeHtml>;
}

@:well.view
typedef PluginPageColumnView = {
    var key:String;
    var label:String;
}

@:well.view
typedef PluginPageActionView = {
    var href:Url;
    var label:String;
    @:optional var download:Bool;
}

@:well.view
typedef PluginPageRowActionView = {
    var label:String;
    var path:String;
    var confirm:String;
}

/** The generic table plugins render on `Admin/PluginPage`; texts are keys in `namespace`. */
@:well.view
typedef PluginPageView = {
    @:optional var namespace:String;
    var title:String;
    var description:String;
    var total:Int;
    var columns:Array<PluginPageColumnView>;
    var rows:Array<Map<String, Dynamic>>;
    var actions:Array<PluginPageActionView>;
    @:optional var rowAction:PluginPageRowActionView;
    var pagination:PageLinksView;
    var noun:String;
}
