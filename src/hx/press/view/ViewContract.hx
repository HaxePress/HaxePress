package hx.press.view;

import wellout.check.HostContract;
import wellout.check.Types;
import wellout.macro.ViewSchema;

/**
    What HaxePress templates may read and call: the view types under
    `hx.press.view.types`, the implicit roots, helpers, filters and
    islands. Templates are checked against it when they are compiled.
**/
class ViewContract {
    public static function build():HostContract {
        var contract = ViewSchema.registerPackage(new HostContract(), "hx.press.view.types");
        contract.addRoot("site", TView("SiteView"));
        contract.addRoot("i18n", TView("I18nView"));
        contract.addRoot("languages", TView("LanguagesView"));
        contract.addRoot("seo", TNullable(TView("SeoView")));
        contract.addRoot("auth", TNullable(TView("AuthView")));
        contract.addRoot("request", TView("RequestView"));
        contract.addRoot("theme", TNullable(TView("ThemeView")));
        contract.addRoot("navigation", TMap(TList(TView("NavigationLinkView"))));
        contract.addRoot("pluginNavigation", TView("PluginNavigationView"));
        contract.addRoot("extensions", TView("ExtensionsView"));
        contract.addRoot("adminNavigation", TList(TView("AdminNavigationGroupView")));
        contract.addRoot("errors", TMap(TString));
        contract.addRoot("primaryArchive", TUrl);
        contract.addRoot("siteUrl", TString);
        contract.addRoot("csrfToken", TString);
        contract.addRoot("pluginRestartRequired", TBool);
        contract.addRoot("adminSidebar", TList(TView("AdminSidebarGroupView")));
        contract.addRoot("adminLocation", TView("AdminLocationView"));
        contract.addRoot("translations", TUrl);
        var text = (name:String) -> new Parameter(name, TString);
        contract.addHelper(new HelperSignature("t", [text("key")], TString, true));
        contract.addHelper(new HelperSignature("can", [text("capability")], TBool));
        contract.addHelper(new HelperSignature("icon", [text("name")], TSafeHtml));
        contract.addHelper(new HelperSignature("markdown", [text("content")], TSafeHtml));
        contract.addHelper(new HelperSignature("asset", [text("path")], TUrl));
        contract.addHelper(new HelperSignature("url", [new Parameter("path", TString)], TUrl,
            true));
        contract.addHelper(new HelperSignature("query", [text("name")], TString));
        contract.addHelper(new HelperSignature("old", [text("field")], TNullable(TString)));
        contract.addHelper(new HelperSignature("error", [text("field")], TNullable(TString)));
        contract.addHelper(new HelperSignature("year", [], TInt));
        contract.addHelper(new HelperSignature("initials", [text("name")], TString));
        contract.addHelper(new HelperSignature("join", [
            new Parameter("items", TList(TString)),
            new Parameter("separator", TString, true)
        ], TString));
        contract.addHelper(new HelperSignature("active", [
            new Parameter("href", TString),
            new Parameter("exact", TBool, true),
            new Parameter("paths", TNullable(TList(TString)), true)
        ], TBool));
        contract.addHelper(new HelperSignature("fieldValues", [
            new Parameter("definitions", TNullable(TList(TView("FieldDefinitionView")))),
            new Parameter("values", TNullable(TMap(TAny)))
        ], TList(TView("FieldValueView"))));
        contract.addHelper(new HelperSignature("themeVariables", [], TMap(TString)));
        contract.addHelper(new HelperSignature("defaultNavigation", [],
            TList(TView("NavigationLinkView"))));
        contract.addHelper(new HelperSignature("isCurrent", [text("url")], TBool));
        contract.addHelper(new HelperSignature("returnPath", [], TString));
        contract.addHelper(new HelperSignature("size",
            [new Parameter("items", TNullable(TList(TAny)))], TInt));
        contract.addHelper(new HelperSignature("any", [new Parameter("values", TAny)], TBool));
        contract.addFilter(new FilterSignature("encode", TString, [], TString));
        contract.addFilter(new FilterSignature("string", TAny, [], TString));
        contract.addFilter(new FilterSignature("replace", TString,
            [text("search"), text("replacement")], TString));
        contract.addFilter(new FilterSignature("variables", TMap(TString), [], TString));
        contract.addCssFilter("variables");
        contract.addHelper(new HelperSignature("themeAsset", [text("path")], TUrl));
        contract.addHelper(new HelperSignature("packageAsset", [text("path")], TUrl));
        contract.addFilter(new FilterSignature("slice", TString,
            [new Parameter("start", TInt), new Parameter("end", TInt, true)], TString));
        contract.addFilter(new FilterSignature("pixels", TNullable(TString), [
            new Parameter("minimum", TInt),
            new Parameter("maximum", TInt),
            new Parameter("fallback", TInt)
        ], TString));
        contract.addFilter(new FilterSignature("cssVariables", TAny, [], TString));
        contract.addCssFilter("cssVariables");
        contract.addHelper(new HelperSignature("designLink",
            [new Parameter("value", TNullable(TString))], TUrl));
        contract.addHelper(new HelperSignature("designImage",
            [new Parameter("value", TNullable(TString))], TUrl));
        contract.addHelper(new HelperSignature("designStylesheet", [], TUrl));
        contract.addHelper(new HelperSignature("withFeatured", [
            new Parameter("featured", TNullable(TView("ContentItemView"))),
            new Parameter("items", TList(TView("ContentItemView")))
        ], TList(TView("ContentItemView"))));
        contract.addRoot("themeFeeds", TMap(TList(TView("ContentItemView"))));
        contract.addHelper(new HelperSignature("canvasName", [], TString));
        contract.addHelper(new HelperSignature("pageProps", [], TAny));
        contract.addHelper(new HelperSignature("canvasShared", [], TAny));
        contract.addFilter(new FilterSignature("json", TAny, [], TString));
        // t() with the catalogue of a plugin or theme first, such as the texts of a plugin page.
        contract.addHelper(new HelperSignature("translate", [text("namespace"), text("key")],
            TString, true));
        ViewIslands.register(contract);
        return contract;
    }
}
