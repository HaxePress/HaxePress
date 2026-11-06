package hx.press.view;

import haxe.crypto.Md5;
import haxe.ds.ObjectMap;
import hx.press.media.MediaReferences;
import hx.press.themes.ThemeAssets;
import hx.press.themes.ThemeDesignData;
import hx.well.http.AbstractResponse;
import hx.well.http.Request;
import hx.well.http.ResponseBuilder;
import hx.well.http.StringResponse;
import wellout.check.ComponentLibrary;
import wellout.render.TemplateSet;
#if (target.threaded)
import sys.thread.Mutex;
#end

/** A visual design compiled for rendering: its templates and its stylesheet. */
class CompiledDesign {
    public final set:TemplateSet;
    public final stylesheet:String;
    public final css:String;

    public function new(set:TemplateSet, stylesheet:String, css:String) {
        this.set = set;
        this.stylesheet = stylesheet;
        this.css = css;
    }
}

/**
    Visual builder themes: each published design document is turned into
    Wellout templates once (`DesignTemplates`) and its styles into one
    versioned stylesheet (`DesignStyles`). Parsed documents are shared
    objects that change only when the stored design changes, so compiled
    designs are cached by document identity.
**/
class DesignViews {
    static inline final MAX_DESIGNS = 16;

    static final designs = new ObjectMap<Dynamic, CompiledDesign>();
    static var count = 0;
    static final stylesheets:Map<String, String> = [];
    #if (target.threaded)
    static final lock = new Mutex();
    #end

    public static function compiled(themeId:String, document:Dynamic):CompiledDesign {
        #if (target.threaded)
        lock.acquire();
        #end
        var found = designs.get(document);
        #if (target.threaded)
        lock.release();
        #end
        if (found != null) {
            return found;
        }
        var library = new ComponentLibrary(ViewEngine.contract, ViewEngine.library, false);
        for (name => source in DesignTemplates.generate(document)) {
            library.add(name, source);
        }
        var css = DesignStyles.css(document);
        var file = '${themeId}-${Md5.encode(css).substr(0, 16)}.css';
        var design = new CompiledDesign(new TemplateSet(ViewEngine.contract, ViewEngine.runtime,
            library),
            '/theme-design/${file}', css);
        #if (target.threaded)
        lock.acquire();
        #end
        if (count >= MAX_DESIGNS) {
            designs.clear();
            count = 0;
        }
        designs.set(document, design);
        count++;
        stylesheets.set(file, css);
        #if (target.threaded)
        lock.release();
        #end
        return design;
    }

    /** Serves a design stylesheet by its content-hashed name. **/
    public static function serveStylesheet(request:Request):AbstractResponse {
        var file = request.route("file");
        if (!~/^[A-Za-z0-9_-]{1,120}-[0-9a-f]{16}\.css$/.match(file)) {
            return ResponseBuilder.asJson({error: "Unknown stylesheet"}, 404);
        }
        #if (target.threaded)
        lock.acquire();
        #end
        var css = stylesheets.get(file);
        #if (target.threaded)
        lock.release();
        #end
        if (css == null) {
            var themeId = file.substr(0, file.lastIndexOf("-"));
            for (preview in [false, true]) {
                var document = ThemeDesignData.published(themeId, preview);
                if (document != null
                    && compiled(themeId, document).stylesheet == '/theme-design/${file}') {
                    css = stylesheets.get(file);
                }
            }
        }
        if (css == null) {
            return ResponseBuilder.asJson({error: "Unknown stylesheet"}, 404);
        }
        var response = new StringResponse(css, 200);
        response.header("Content-Type", "text/css; charset=utf-8");
        response.header("Cache-Control", "public, max-age=31536000, immutable");
        return response;
    }

    /** A link a design may write: an internal path, a fragment, or a web, email or phone link. **/
    public static function link(value:Null<String>):String {
        if (value == null || value == "") {
            return "";
        }
        return ~/^(\/(?!\/)|#[A-Za-z]|https?:\/\/|mailto:|tel:)/.match(value)
            && !~/[\x00-\x20\x7f\\]/.match(value) ? value : "";
    }

    /** An image a design may show: managed media or the theme's own assets. **/
    public static function image(value:Null<String>):String {
        if (value == null || value == "") {
            return "";
        }
        return MediaReferences.imageUrl(value) || ThemeAssets.imageUrl(value) ? value : "";
    }
}
