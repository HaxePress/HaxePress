package hx.press.view.types.admin;

/** Records read by the settings, tags, navigation, team, activity and account pages. */
@:well.view
typedef AdminSettingsFormView = {
    var site_name:String;
    var site_logo:String;
    var publisher_name:String;
    var description:String;
    var about_site:String;
    var locale:String;
    var home_mode:String;
    var home_type:String;
    var home_page:String;
    var home_size:String;
    var home_template:String;
}

/** A collection offered by a select: its key and its untranslated name. */
@:well.view
typedef AdminCollectionChoiceView = {
    var key:String;
    var name:String;
}

/** The published content item a picker has selected. */
@:well.view
typedef AdminContentChoiceView = {
    var id:Int;
    var title:String;
}

/** Upload limits for the site logo field, as `MediaReferences.rules()` returns them. */
@:well.view
typedef SettingsMediaRulesView = {
    var uploadUrl:String;
    var maxBytes:Int;
    var mimeTypes:Array<String>;
    var extensions:Array<String>;
    var imagePattern:String;
}

@:well.view
typedef AdminTagView = {
    var id:Int;
    var name:String;
    var slug:String;
    var description:String;
    var items:Int;
}

@:well.view
typedef AdminTagFormView = {
    var id:String;
    var name:String;
    var slug:String;
    var description:String;
}

@:well.view
typedef AdminMenuLinkView = {
    var id:Int;
    var label:String;
    var url:String;
    var position:Int;
    var new_tab:Int;
    var content_id:Int;
    var collection_key:String;
}

@:well.view
typedef AdminNavigationRegionView = {
    var key:String;
    var name:String;
    var max_links:Int;
    var enabled:Int;
    var system:Int;
}

/** The link form: the edited link or a new one, and its target (`url`, `content` or `collection`). */
@:well.view
typedef AdminMenuLinkFormView = {
    var id:String;
    var label:String;
    var url:String;
    var position:String;
    var content_id:String;
    var collection_key:String;
    var new_tab:Bool;
    var mode:String;
}

@:well.view
typedef AdminNavigationRegionFormView = {
    var key:String;
    var name:String;
    var max_links:String;
    var enabled:Bool;
}

/** A team member; `roleLabel` is the translation key of the role. */
@:well.view
typedef AdminTeamMemberView = {
    var id:Int;
    var name:String;
    var email:String;
    var role:String;
    var active:Int;
    var roleLabel:String;
}

@:well.view
typedef AdminRoleChoiceView = {
    var key:String;
    var name:String;
    var enabled:Int;
}

/** The member form; `own` marks the signed-in account, whose password is changed from Account. */
@:well.view
typedef AdminTeamMemberFormView = {
    var id:String;
    var name:String;
    var email:String;
    var role:String;
    var active:Bool;
    var own:Bool;
}

/** An activity entry with its translation key and its `datetime` attribute value. */
@:well.view
typedef AdminActivityEntryView = {
    var id:Int;
    var actor:String;
    var action:String;
    var entity:String;
    var entity_id:Int;
    var label:String;
    var created_at:String;
    var actionKey:String;
    var datetime:String;
}

/** An option of the activity filter; `label` is a translation key. */
@:well.view
typedef AdminActivityFilterView = {
    var value:String;
    var label:String;
}

@:well.view
typedef AdminAccountMemberView = {
    var name:String;
    var email:String;
    var role:String;
    var roleLabel:String;
}
