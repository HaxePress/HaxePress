package hx.press.view;

import hx.well.http.Request;
import wellout.check.ComponentLibrary;
import wellout.check.HostContract;
import wellout.render.Runtime;
import wellout.render.TemplateSet;

/** Where a page is rendered from: a template set, the template name and its host settings. */
class ViewTarget {
    public final set:TemplateSet;
    public final template:String;
    public final namespace:String;
    public final assetBase:Null<String>;
    public final mapper:Null<String->String>;

    /** Theme templates installed at runtime render within output and depth budgets. **/
    public final untrusted:Bool;

    /** Module URLs of a plugin's own islands, by island name. **/
    public final islands:Null<Map<String, String>>;

    public function new(set:TemplateSet, template:String, namespace:String, ?assetBase:String,
            ?mapper:String->String, untrusted:Bool = false, ?islands:Map<String, String>) {
        this.set = set;
        this.template = template;
        this.namespace = namespace;
        this.assetBase = assetBase;
        this.mapper = mapper;
        this.untrusted = untrusted;
        this.islands = islands;
    }
}

/**
    The contract, runtime and template sets of HaxePress. Application
    templates are compiled once on first use. Themes add their own sets
    over the application components (`ThemeViews`).
**/
class ViewEngine {
    public static final contract:HostContract = ViewContract.build();
    public static final runtime:Runtime = ViewHelpers.runtime();
    public static final library:ComponentLibrary = applicationLibrary();
    public static final application:TemplateSet = new TemplateSet(contract, runtime, library);

    static function applicationLibrary():ComponentLibrary {
        var templates = new ComponentLibrary(contract);
        for (name in ViewSources.names()) {
            templates.add(name, ViewSources.source(name));
        }
        return templates;
    }

    public static function target(name:String, request:Null<Request>):ViewTarget {
        // Public pages use the theme, including theme previews served under /admin.
        var previewing = View.sharedValue(request, "theme") != null;
        if ((previewing || !ViewRoots.isAdmin(request)) && !StringTools.startsWith(name,
            "Admin/")) {
            var themed = ThemeViews.target(name, request);
            if (themed != null) {
                return themed;
            }
        }
        return new ViewTarget(application, name, "cms");
    }
}
