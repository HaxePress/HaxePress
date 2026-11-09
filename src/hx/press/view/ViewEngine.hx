package hx.press.view;

import hx.well.http.Request;
import wellout.check.ComponentLibrary;
import wellout.check.HostContract;
import wellout.render.Runtime;
import wellout.render.TemplateSet;
import wellout.render.TemplateStore;
#if php
import hx.press.BuildIdentity;
import hx.well.facades.Storage;
import wellout.render.PhpTemplateStore;
#end

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
    public static final application:TemplateSet = new TemplateSet(contract, runtime, library,
        store("application"));

    /**
        Where a set keeps its compiled templates between processes: Wellout's
        PHP files in `private/storage/cache/views` on PHP, which starts the
        application for each request; none on the JVM, which compiles each
        template once per process. `version` names the set and the sources
        of its templates; this build is part of it.
    **/
    public static function store(version:String):Null<TemplateStore> {
        #if php
        return new PhpTemplateStore(cacheRoot(), '${BuildIdentity.id}\n${version}');
        #else
        return null;
        #end
    }

    #if php
    static var templateCache:Null<String> = null;

    /** The template cache folder, resolved through the local disk once per request. **/
    static function cacheRoot():String {
        if (templateCache == null) {
            templateCache = Storage.disk("local").path("cache/views");
        }
        return templateCache;
    }
    #end

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
