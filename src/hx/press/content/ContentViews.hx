package hx.press.content;

import hx.press.i18n.Languages;
import hx.well.http.Request;

/**
    What a request tells plugins about the page and its visitor, for
    plugins that count or react to visits with their own middleware.

    A public page that shows a published content item records it while it
    renders, and the `site.shared` hook receives it as `content`. A plugin
    that trusts the connection's proxy, such as the bundled Cloudflare
    plugin, records the visitor's country. The administration marks a
    signed-in member's browser for the whole site. What counts as a visit
    is each plugin's own decision; the bundled View Count plugin shows one.
**/
class ContentViews {
    /** `{id, type}` of the published content item a page shows. **/
    public static inline final CONTENT = "cms.content";

    /**
        The visitor's country as two uppercase letters, set only by a plugin
        that trusts the connection's proxy. Absent when the country is unknown.
    **/
    public static inline final COUNTRY = "cms.visitor.country";

    /**
        Set for the whole site while a member is signed in, because public
        pages run without the administration's session. It grants nothing.
    **/
    public static inline final MEMBER_COOKIE = "cms_member";

    /** Records that the page rendering for `request` shows the published item `id`. **/
    public static function shown(request:Request, id:Int, type:String):Void {
        request.setAttribute(CONTENT, {id: id, type: type});
    }

    /** `{id, type}` of the published item the request's page shows, or null. **/
    public static function content(request:Null<Request>):Dynamic {
        return request == null ? null : request.getAttribute(CONTENT, null);
    }

    /** The visitor's trusted country as two uppercase letters, or null. **/
    public static function country(request:Request):Null<String> {
        var value:Dynamic = request.getAttribute(COUNTRY, null);
        if (!Std.isOfType(value, String)) {
            return null;
        }
        var code:String = value;
        return validCountry(code) ? code : null;
    }

    /** Whether the request comes from a browser where a member is signed in. **/
    /** The language a public page is shown in: its address's language, or the default one. **/
    public static function language(request:Request):String {
        var selected:Null<String> = request.getAttribute(Languages.ATTRIBUTE, null);
        return selected != null && Languages.exists(selected) ? selected : Languages.defaultCode();
    }

    public static function member(request:Request):Bool {
        return request.cookie(MEMBER_COOKIE) != null;
    }

    /** Whether `code` is two uppercase ASCII letters. **/
    public static function validCountry(code:Null<String>):Bool {
        if (code == null || code.length != 2) {
            return false;
        }
        for (index in 0...2) {
            var letter = StringTools.fastCodeAt(code, index);
            if (letter < "A".code || letter > "Z".code) {
                return false;
            }
        }
        return true;
    }
}
