package hx.press.view.types;

import wellout.Url;

/** Site settings; the runtime value is the settings map, read by key. */
@:well.view
typedef SiteView = {
    var site_name:String;
    var site_logo:String;
    var publisher_name:String;
    var description:String;
    var about_site:String;
    var home_mode:String;
    var home_type:String;
    var home_page:String;
    var home_size:String;
    var home_template:String;
}

@:well.view
typedef LocaleChoiceView = {
    var code:String;
    var name:String;
    var direction:String;
}

/** A language visitors can switch to; `href` is the current page in that language. **/
@:well.view
typedef LanguageChoiceView = {
    var code:String;
    var name:String;
    var direction:String;
    var href:String;
    var current:Bool;
}

/**
    The site's public languages. `choices` is empty on a site with one
    public language, which shows no language switcher.
**/
@:well.view
typedef LanguagesView = {
    var multilingual:Bool;
    var current:String;
    var defaultLanguage:String;
    var choices:Array<LanguageChoiceView>;
}

@:well.view
typedef SeoAlternateView = {
    var language:String;
    var href:String;
}

/** Search engine links of a public page; null in the administration. **/
@:well.view
typedef SeoView = {
    var canonical:String;
    var alternates:Array<SeoAlternateView>;
    var ogLocale:String;
    var ogAlternates:Array<String>;
}

@:well.view
typedef I18nView = {
    var locale:String;
    var direction:String;
    var locales:Array<LocaleChoiceView>;
}

@:well.view
typedef AdminUserView = {
    var id:Int;
    var name:String;
    var email:String;
    var role:String;
    var roleLabel:String;
    var capabilities:Array<String>;
}

@:well.view
typedef AuthView = {
    var admin:AdminUserView;
}

/** The current request: its path, the path with its query, and the query values. */
@:well.view
typedef RequestView = {
    var path:String;
    var url:String;
    var method:String;
    var query:Map<String, String>;
}

@:well.view
typedef NavigationLinkView = {
    var id:Int;
    var label:String;
    var url:Url;
    var new_tab:Int;
}

@:well.view
typedef PluginLinkView = {
    var id:String;
    var label:String;
    var href:Url;
    var icon:String;
}

@:well.view
typedef PluginNavigationView = {
    var header:Array<PluginLinkView>;
    var footer:Array<PluginLinkView>;
    var admin:Array<PluginLinkView>;
}

@:well.view
typedef ExtensionAssetView = {
    var id:String;
    var module:Url;
    var stylesheet:Url;
    var settings:Map<String, String>;
}

/**
    The frontend module of an active plugin, which public pages activate
    with its public settings and the messages of its catalogue.
**/
@:well.view
typedef ExtensionModuleView = {
    var id:String;
    var module:Url;
    var settings:Map<String, String>;
    var messages:Map<String, Dynamic>;
}

@:well.view
typedef ExtensionBlockView = {
    var id:String;
    var slot:String;
    var content:String;
}

@:well.view
typedef ExtensionsView = {
    var assets:Array<ExtensionAssetView>;
    var modules:Array<ExtensionModuleView>;
    var blocks:Array<ExtensionBlockView>;
}

@:well.view
typedef ThemeTemplateView = {
    var name:String;
    var label:String;
    var scope:String;
}

@:well.view
typedef ThemeView = {
    var id:String;
    var built_in:Bool;
    var name:String;
    var slug:String;
    var layout:String;
    var stylesheet:Url;
    var module:Url;
    var assetBase:String;
    var settings:Map<String, String>;
    var preview:Bool;
    @:optional var previewBase:String;
    @:optional var customizeSession:String;
    @:optional var studioSession:String;
    @:optional var studioScope:String;
    var templates:Array<ThemeTemplateView>;
    var navigation:Array<String>;
}

@:well.view
typedef AdminNavigationLinkView = {
    var href:Url;
    var label:String;
    var icon:String;
    var exact:Bool;
    @:optional var activePaths:Array<String>;
    @:optional var parent:String;
}

@:well.view
typedef AdminNavigationGroupView = {
    var label:String;
    var links:Array<AdminNavigationLinkView>;
}
